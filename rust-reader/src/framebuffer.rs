use anyhow::Result;
use memmap2::MmapMut;
use std::fs::{File, OpenOptions};
use std::os::unix::io::AsRawFd;
use crate::renderer::RenderBackend;
use nix::ioctl_write_ptr;

// 从 mxcfb.h 移植过来的结构体和常量
#[repr(C)]
#[derive(Debug, Default, Copy, Clone)]
pub struct MxcfbRect {
    pub top: u32,
    pub left: u32,
    pub width: u32,
    pub height: u32,
}

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct MxcfbUpdateData {
    pub update_region: MxcfbRect,
    pub waveform_mode: u32,
    pub update_mode: u32,
    pub update_marker: u32,
    pub temp: i32,
    pub flags: u32,
    pub alt_buffer_data: *mut std::ffi::c_void,
}

impl Default for MxcfbUpdateData {
    fn default() -> Self {
        Self {
            update_region: MxcfbRect::default(),
            waveform_mode: 0,
            update_mode: 0,
            update_marker: 0,
            temp: 0,
            flags: 0,
            alt_buffer_data: std::ptr::null_mut(),
        }
    }
}

// 常量定义
const WAVEFORM_MODE_AUTO: u32 = 257;
const UPDATE_MODE_FULL: u32 = 0;
const TEMP_USE_AMBIENT: i32 = 0x1000;

// 定义 ioctl 命令
const MXCFB_IOCTL_MAGIC: u8 = b'F';
const MXCFB_SEND_UPDATE_IOCTL_NR: u8 = 0x2E;

ioctl_write_ptr!(mxcfb_send_update, MXCFB_IOCTL_MAGIC, MXCFB_SEND_UPDATE_IOCTL_NR, MxcfbUpdateData);

pub struct Framebuffer {
    file: Option<File>,
    buffer: MmapMut,
    width: u32,
    height: u32,
    bytes_per_pixel: u32,
    line_length: u32,
    is_simulation: bool,
}

impl Framebuffer {
    pub fn open(device_path: &str) -> Result<Self> {
        match OpenOptions::new().read(true).write(true).open(device_path) {
            Ok(file) => {
                let (width, height, bytes_per_pixel) = Self::detect_screen_info(&file)?;
                let line_length = width * bytes_per_pixel;
                let buffer = unsafe { MmapMut::map_mut(&file)? };

                Ok(Self {
                    file: Some(file),
                    buffer,
                    width,
                    height,
                    bytes_per_pixel,
                    line_length,
                    is_simulation: false,
                })
            }
            Err(_) => {
                println!("无法打开 {}，切换到模拟模式", device_path);
                let (width, height, bytes_per_pixel) = Self::get_default_screen_info();
                let line_length = width * bytes_per_pixel;
                let buffer_size = (line_length * height) as usize;
                
                // 在模拟模式下，我们需要一个可变的 Vec<u8> 作为 buffer
                // 但 MmapMut 是必须的，所以我们创建一个临时的匿名文件来映射
                let temp_file = tempfile::tempfile()?;
                temp_file.set_len(buffer_size as u64)?;
                let mut buffer = unsafe { MmapMut::map_mut(&temp_file)? };
                buffer.fill(0xFF); // 白色背景

                Ok(Self {
                    file: None,
                    buffer,
                    width,
                    height,
                    bytes_per_pixel,
                    line_length,
                    is_simulation: true,
                })
            }
        }
    }

    fn detect_screen_info(_file: &File) -> Result<(u32, u32, u32)> {
        Ok(Self::get_default_screen_info())
    }

    fn get_default_screen_info() -> (u32, u32, u32) {
        let width = std::env::var("KINDLE_WIDTH").unwrap_or_else(|_| "1072".to_string()).parse::<u32>().unwrap_or(1072);
        let height = std::env::var("KINDLE_HEIGHT").unwrap_or_else(|_| "1448".to_string()).parse::<u32>().unwrap_or(1448);
        let bpp = std::env::var("KINDLE_BPP").unwrap_or_else(|_| "1".to_string()).parse::<u32>().unwrap_or(1);
        println!("检测到屏幕: {}x{}, {}bpp", width, height, bpp * 8);
        (width, height, bpp)
    }

    pub fn full_refresh(&self) -> Result<()> {
        if self.is_simulation {
            println!("模拟模式：触发屏幕刷新");
            self.debug_output();
        } else if let Some(file) = &self.file {
            println!("触发真实屏幕刷新...");
            let update_rect = MxcfbRect {
                top: 0,
                left: 0,
                width: self.width,
                height: self.height,
            };

            let mut update_data = MxcfbUpdateData {
                update_region: update_rect,
                waveform_mode: WAVEFORM_MODE_AUTO,
                update_mode: UPDATE_MODE_FULL,
                update_marker: 0,
                temp: TEMP_USE_AMBIENT,
                flags: 0,
                ..Default::default()
            };

            unsafe {
                mxcfb_send_update(file.as_raw_fd(), &mut update_data)?;
            }
            println!("屏幕刷新指令已发送");
        }
        Ok(())
    }

    fn debug_output(&self) {
        println!("=== 屏幕内容预览 ===");
        let sample_lines = 10;
        let chars_per_line = 80;
        for y in 0..sample_lines.min(self.height) {
            let mut line = String::new();
            for x in 0..chars_per_line.min(self.width) {
                let offset = (y * self.line_length + x * self.bytes_per_pixel) as usize;
                if offset < self.buffer.len() {
                    let pixel = self.buffer[offset];
                    let char = if pixel < 128 { '#' } else { ' ' };
                    line.push(char);
                } else {
                    line.push(' ');
                }
            }
            println!("{}", line);
        }
        println!("=== 预览结束 ===");
    }
}

impl RenderBackend for Framebuffer {
    fn resolution(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    fn draw_bitmap(&mut self, bitmap: &[u8]) {
        let copy_size = self.buffer.len().min(bitmap.len());
        self.buffer[..copy_size].copy_from_slice(&bitmap[..copy_size]);
        if self.is_simulation {
            println!("模拟模式：已更新 framebuffer ({} 字节)", copy_size);
        }
    }

    fn clear(&mut self) {
        self.buffer.fill(0xFF);
        if self.is_simulation {
            println!("模拟模式：已清空 framebuffer");
        }
    }

    fn refresh(&mut self) -> Result<()> {
        self.full_refresh()
    }

    fn is_desktop(&self) -> bool {
        false
    }
}
 