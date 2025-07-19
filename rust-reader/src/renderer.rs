use anyhow::Result;

// 渲染后端抽象
pub trait RenderBackend {
    fn resolution(&self) -> (u32, u32);
    fn draw_bitmap(&mut self, bitmap: &[u8]);
    fn clear(&mut self);
    fn refresh(&mut self) -> Result<()>;
    fn is_desktop(&self) -> bool { false }
}

// 统一的渲染器
pub struct Renderer {
    backend: Box<dyn RenderBackend>,
}

impl Renderer {
    pub fn new() -> Result<Self> {
        let backend = Self::create_backend()?;
        Ok(Self { backend })
    }

    fn create_backend() -> Result<Box<dyn RenderBackend>> {
        // 根据运行环境选择后端
        #[cfg(feature = "desktop")]
        {
            // 优先尝试 SDL2（桌面环境）
            if let Ok(sdl_renderer) = crate::sdl_renderer::SDL2Renderer::new() {
                println!("使用 SDL2 渲染后端（桌面模式）");
                return Ok(Box::new(sdl_renderer));
            }
        }

        // 回退到 framebuffer（嵌入式设备）
        match crate::framebuffer::Framebuffer::open("/dev/fb0") {
            Ok(fb) => {
                println!("使用 Framebuffer 渲染后端（嵌入式模式）");
                Ok(Box::new(fb))
            }
            Err(e) => {
                println!("无法初始化任何渲染后端: {}", e);
                anyhow::bail!("无法初始化渲染后端")
            }
        }
    }

    pub fn resolution(&self) -> (u32, u32) {
        self.backend.resolution()
    }

    pub fn draw_bitmap(&mut self, bitmap: &[u8]) {
        self.backend.draw_bitmap(bitmap);
    }

    pub fn clear(&mut self) {
        self.backend.clear();
    }

    pub fn refresh(&mut self) -> Result<()> {
        self.backend.refresh()
    }

    pub fn is_desktop(&self) -> bool {
        self.backend.is_desktop()
    }
}