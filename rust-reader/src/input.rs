use anyhow::Result;
use std::fs::File;
use std::io::Read;
use std::path::Path;

#[derive(Debug, Clone)]
pub enum InputEvent {
    NextPage,
    PrevPage,
    Quit,
    Unknown,
}

// Linux input event 结构
#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct LinuxInputEvent {
    time: libc::timeval,
    type_: u16,
    code: u16,
    value: i32,
}

// Linux input 常量
const EV_KEY: u16 = 1;
const EV_ABS: u16 = 3;

// 按键码
const KEY_PAGEUP: u16 = 104;
const KEY_PAGEDOWN: u16 = 109;
const KEY_LEFT: u16 = 105;
const KEY_RIGHT: u16 = 106;
const KEY_UP: u16 = 103;
const KEY_DOWN: u16 = 108;
const KEY_ESC: u16 = 1;
const KEY_Q: u16 = 16;

// 触摸事件
const ABS_X: u16 = 0;
const ABS_Y: u16 = 1;
const BTN_TOUCH: u16 = 330;

pub struct InputDevice {
    device: File,
    screen_width: u32,
    screen_height: u32,
    touch_state: TouchState,
}

#[derive(Debug, Clone)]
struct TouchState {
    x: i32,
    y: i32,
    is_pressed: bool,
    last_press_pos: Option<(i32, i32)>,
}

impl InputDevice {
    pub fn auto_detect() -> Result<Self> {
        // 尝试找到第一个可用的输入设备
        let input_dir = Path::new("/dev/input");
        
        if let Ok(entries) = std::fs::read_dir(input_dir) {
            for entry in entries {
                let entry = entry?;
                let path = entry.path();
                
                if let Some(filename) = path.file_name() {
                    if let Some(name) = filename.to_str() {
                        if name.starts_with("event") {
                            println!("尝试打开输入设备: {:?}", path);
                            
                            match File::open(&path) {
                                Ok(device) => {
                                    println!("成功打开输入设备: {:?}", path);
                                    return Ok(Self {
                                        device,
                                        screen_width: 1448, // 默认值，可通过环境变量调整
                                        screen_height: 1072,
                                        touch_state: TouchState {
                                            x: 0,
                                            y: 0,
                                            is_pressed: false,
                                            last_press_pos: None,
                                        },
                                    });
                                }
                                Err(e) => {
                                    eprintln!("无法打开 {:?}: {}", path, e);
                                    continue;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 如果无法找到真实输入设备，创建模拟输入设备
        println!("无法找到真实输入设备，创建模拟输入设备");
        Self::create_simulation_device()
    }

    fn create_simulation_device() -> Result<Self> {
        // 创建一个模拟的输入设备
        // 在模拟模式下，我们将使用标准输入来模拟按键
        use std::io::{self, Write};
        
        println!("=== 模拟输入模式 ===");
        println!("使用以下按键:");
        println!("  n/空格 - 下一页");
        println!("  p/b - 上一页");
        println!("  q - 退出");
        println!("==================");
        
        // 创建一个假的文件句柄（实际上不会被使用）
        let dummy_file = std::fs::File::open("/dev/null")
            .or_else(|_| std::fs::File::open("NUL")) // Windows 兼容
            .or_else(|_| {
                // 如果都失败了，创建一个临时文件
                std::fs::File::create("temp_input_simulation")
            })?;
        
        Ok(Self {
            device: dummy_file,
            screen_width: 1448,
            screen_height: 1072,
            touch_state: TouchState {
                x: 0,
                y: 0,
                is_pressed: false,
                last_press_pos: None,
            },
        })
    }

    pub fn wait_event(&mut self) -> Result<InputEvent> {
        // 检查是否是模拟模式
        if self.is_simulation_mode() {
            return self.wait_simulation_event();
        }

        loop {
            let mut buffer = [0u8; std::mem::size_of::<LinuxInputEvent>()];
            match self.device.read_exact(&mut buffer) {
                Ok(_) => {
                    let event: LinuxInputEvent = unsafe {
                        std::ptr::read(buffer.as_ptr() as *const LinuxInputEvent)
                    };

                    if let Some(input_event) = self.process_event(event) {
                        return Ok(input_event);
                    }
                }
                Err(_) => {
                    // 如果读取失败，可能是设备不可用，切换到模拟模式
                    return self.wait_simulation_event();
                }
            }
        }
    }

    fn is_simulation_mode(&self) -> bool {
        // 简单的启发式检查：尝试读取设备元数据
        // 如果失败，很可能是模拟模式
        use std::os::unix::io::AsRawFd;
        
        // 在非 Unix 系统上，总是使用模拟模式
        if cfg!(not(unix)) {
            return true;
        }
        
        // 尝试获取文件描述符
        let fd = self.device.as_raw_fd();
        if fd < 0 {
            return true;
        }
        
        // 检查是否是真实的输入设备
        // 这里简化处理，可以根据需要添加更多检查
        false
    }

    fn wait_simulation_event(&mut self) -> Result<InputEvent> {
        use std::io::{self, BufRead, Write};
        
        print!("请输入命令 (n=下一页, p=上一页, q=退出): ");
        io::stdout().flush()?;
        
        let stdin = io::stdin();
        let mut line = String::new();
        stdin.read_line(&mut line)?;
        
        let command = line.trim().to_lowercase();
        match command.as_str() {
            "n" | "next" | " " | "" => {
                println!("模拟输入: 下一页");
                Ok(InputEvent::NextPage)
            }
            "p" | "prev" | "b" | "back" => {
                println!("模拟输入: 上一页");
                Ok(InputEvent::PrevPage)
            }
            "q" | "quit" | "exit" => {
                println!("模拟输入: 退出");
                Ok(InputEvent::Quit)
            }
            _ => {
                println!("未知命令: {}", command);
                Ok(InputEvent::Unknown)
            }
        }
    }

    fn process_event(&mut self, event: LinuxInputEvent) -> Option<InputEvent> {
        match event.type_ {
            EV_KEY => self.process_key_event(event),
            EV_ABS => self.process_touch_event(event),
            _ => None,
        }
    }

    fn process_key_event(&mut self, event: LinuxInputEvent) -> Option<InputEvent> {
        // 只处理按键按下事件 (value = 1)
        if event.value != 1 {
            return None;
        }

        match event.code {
            KEY_PAGEDOWN | KEY_RIGHT | KEY_DOWN => {
                println!("检测到下一页按键");
                Some(InputEvent::NextPage)
            }
            KEY_PAGEUP | KEY_LEFT | KEY_UP => {
                println!("检测到上一页按键");
                Some(InputEvent::PrevPage)
            }
            KEY_ESC | KEY_Q => {
                println!("检测到退出按键");
                Some(InputEvent::Quit)
            }
            _ => {
                println!("未知按键: {}", event.code);
                None
            }
        }
    }

    fn process_touch_event(&mut self, event: LinuxInputEvent) -> Option<InputEvent> {
        match event.code {
            ABS_X => {
                self.touch_state.x = event.value;
                None
            }
            ABS_Y => {
                self.touch_state.y = event.value;
                None
            }
            BTN_TOUCH => {
                if event.value == 1 {
                    // 触摸按下
                    self.touch_state.is_pressed = true;
                    self.touch_state.last_press_pos = Some((self.touch_state.x, self.touch_state.y));
                    println!("触摸按下: ({}, {})", self.touch_state.x, self.touch_state.y);
                    None
                } else if event.value == 0 {
                    // 触摸抬起
                    self.touch_state.is_pressed = false;
                    
                    if let Some((press_x, press_y)) = self.touch_state.last_press_pos {
                        let current_x = self.touch_state.x;
                        let current_y = self.touch_state.y;
                        
                        println!("触摸抬起: ({}, {}) -> ({}, {})", press_x, press_y, current_x, current_y);
                        
                        // 简单的手势识别：根据触摸位置判断翻页
                        // 屏幕左半部分：上一页，右半部分：下一页
                        let screen_center_x = self.screen_width as i32 / 2;
                        
                        if current_x < screen_center_x {
                            println!("检测到左侧触摸 - 上一页");
                            Some(InputEvent::PrevPage)
                        } else {
                            println!("检测到右侧触摸 - 下一页");
                            Some(InputEvent::NextPage)
                        }
                    } else {
                        None
                    }
                } else {
                    None
                }
            }
            _ => None,
        }
    }
}

impl TouchState {
    fn new() -> Self {
        Self {
            x: 0,
            y: 0,
            is_pressed: false,
            last_press_pos: None,
        }
    }
}