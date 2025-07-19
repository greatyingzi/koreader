#[cfg(feature = "desktop")]
use anyhow::Result;
#[cfg(feature = "desktop")]
use sdl2::{pixels::PixelFormatEnum, render::Canvas, video::Window, EventPump, Sdl};
#[cfg(feature = "desktop")]
use crate::renderer::RenderBackend;

#[cfg(feature = "desktop")]
pub struct SDL2Renderer {
    _sdl_context: Sdl,
    canvas: Canvas<Window>,
    event_pump: EventPump,
    width: u32,
    height: u32,
    buffer: Vec<u8>,
}

#[cfg(feature = "desktop")]
impl SDL2Renderer {
    pub fn new() -> Result<Self> {
        let sdl_context = sdl2::init().map_err(|e| anyhow::anyhow!("SDL2 初始化失败: {}", e))?;
        let video_subsystem = sdl_context
            .video()
            .map_err(|e| anyhow::anyhow!("SDL2 视频子系统初始化失败: {}", e))?;

        // 默认窗口大小（可通过环境变量调整）
        let width = std::env::var("READER_WINDOW_WIDTH")
            .unwrap_or_else(|_| "800".to_string())
            .parse::<u32>()
            .unwrap_or(800);

        let height = std::env::var("READER_WINDOW_HEIGHT")
            .unwrap_or_else(|_| "600".to_string())
            .parse::<u32>()
            .unwrap_or(600);

        let window = video_subsystem
            .window("Kindle Reader", width, height)
            .position_centered()
            .resizable()
            .build()
            .map_err(|e| anyhow::anyhow!("SDL2 窗口创建失败: {}", e))?;

        let canvas = window
            .into_canvas()
            .accelerated()
            .present_vsync()
            .build()
            .map_err(|e| anyhow::anyhow!("SDL2 画布创建失败: {}", e))?;

        let event_pump = sdl_context
            .event_pump()
            .map_err(|e| anyhow::anyhow!("SDL2 事件泵创建失败: {}", e))?;

        // 初始化缓冲区（灰度图像）
        let buffer_size = (width * height) as usize;
        let buffer = vec![255u8; buffer_size]; // 白色背景

        println!("SDL2 渲染器初始化成功: {}x{}", width, height);

        Ok(Self {
            _sdl_context: sdl_context,
            canvas,
            event_pump,
            width,
            height,
            buffer,
        })
    }

    pub fn get_event_pump(&mut self) -> &mut EventPump {
        &mut self.event_pump
    }

    fn grayscale_to_rgb(&self, grayscale_data: &[u8]) -> Vec<u8> {
        let mut rgb_data = Vec::with_capacity(grayscale_data.len() * 3);
        
        for &gray in grayscale_data {
            // 将灰度值转换为 RGB
            rgb_data.push(gray); // R
            rgb_data.push(gray); // G
            rgb_data.push(gray); // B
        }
        
        rgb_data
    }
}

#[cfg(feature = "desktop")]
impl RenderBackend for SDL2Renderer {
    fn resolution(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    fn draw_bitmap(&mut self, bitmap: &[u8]) {
        // 更新内部缓冲区
        let copy_size = self.buffer.len().min(bitmap.len());
        self.buffer[..copy_size].copy_from_slice(&bitmap[..copy_size]);

        // 转换为 RGB 格式并绘制到画布
        let rgb_data = self.grayscale_to_rgb(&self.buffer);
        
        // 创建纹理并绘制
        let texture_creator = self.canvas.texture_creator();
        
        if let Ok(mut texture) = texture_creator.create_texture_streaming(
            PixelFormatEnum::RGB24,
            self.width,
            self.height,
        ) {
            if let Ok(_) = texture.with_lock(None, |buffer: &mut [u8], _pitch: usize| {
                buffer.copy_from_slice(&rgb_data);
            }) {
                let _ = self.canvas.copy(&texture, None, None);
            }
        };
    }

    fn clear(&mut self) {
        // 清空缓冲区为白色
        self.buffer.fill(255);
        
        // 清空画布
        self.canvas.set_draw_color(sdl2::pixels::Color::WHITE);
        let _ = self.canvas.clear();
    }

    fn refresh(&mut self) -> Result<()> {
        // SDL2 的 present 相当于刷新
        self.canvas.present();
        Ok(())
    }

    fn is_desktop(&self) -> bool {
        true
    }
}

// 在没有 desktop feature 时提供空实现
#[cfg(not(feature = "desktop"))]
pub struct SDL2Renderer;

#[cfg(not(feature = "desktop"))]
impl SDL2Renderer {
    pub fn new() -> Result<Self> {
        anyhow::bail!("SDL2 渲染器在嵌入式模式下不可用")
    }
}
