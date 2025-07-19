use font8x8::{BASIC_FONTS, UnicodeFonts};

pub struct Font {
    char_width: u32,
    char_height: u32,
}

impl Font {
    pub fn new() -> Self {
        Self {
            char_width: 8,
            char_height: 8,
        }
    }

    pub fn char_dimensions(&self) -> (u32, u32) {
        (self.char_width, self.char_height)
    }

    pub fn render_char(&self, c: char) -> Option<[u8; 8]> {
        BASIC_FONTS.get(c)
    }

    pub fn render_text(&self, text: &str, width: u32, height: u32) -> Vec<u8> {
        let chars_per_line = (width / self.char_width) as usize;
        let lines_per_page = (height / self.char_height) as usize;
        
        let mut bitmap = vec![0xFF; (width * height) as usize]; // 白色背景
        
        let mut x = 0;
        let mut y = 0;
        
        for c in text.chars() {
            if c == '\n' {
                x = 0;
                y += 1;
                if y >= lines_per_page {
                    break;
                }
                continue;
            }
            
            if c == '\r' {
                continue;
            }
            
            if x >= chars_per_line {
                x = 0;
                y += 1;
                if y >= lines_per_page {
                    break;
                }
            }
            
            if y >= lines_per_page {
                break;
            }
            
            if let Some(glyph) = self.render_char(c) {
                self.draw_glyph(&mut bitmap, &glyph, (x as u32) * self.char_width, (y as u32) * self.char_height, width);
            }
            
            x += 1;
        }
        
        bitmap
    }
    
    fn draw_glyph(&self, bitmap: &mut [u8], glyph: &[u8; 8], start_x: u32, start_y: u32, width: u32) {
        for (row, &byte) in glyph.iter().enumerate() {
            for col in 0..8 {
                if (byte >> col) & 1 == 1 {
                    let x = start_x + (7 - col) as u32; // 反转位序
                    let y = start_y + row as u32;
                    let offset = (y * width + x) as usize;
                    
                    if offset < bitmap.len() {
                        bitmap[offset] = 0x00; // 黑色像素
                    }
                }
            }
        }
    }

    pub fn text_dimensions(&self, text: &str, max_width: u32) -> (u32, u32) {
        let chars_per_line = (max_width / self.char_width) as usize;
        let mut lines = 1;
        let mut current_line_chars = 0;
        let mut max_line_chars = 0;
        
        for c in text.chars() {
            if c == '\n' {
                lines += 1;
                max_line_chars = max_line_chars.max(current_line_chars);
                current_line_chars = 0;
            } else if c != '\r' {
                current_line_chars += 1;
                if current_line_chars >= chars_per_line {
                    lines += 1;
                    max_line_chars = max_line_chars.max(current_line_chars);
                    current_line_chars = 0;
                }
            }
        }
        
        max_line_chars = max_line_chars.max(current_line_chars);
        
        (
            (max_line_chars as u32 * self.char_width).min(max_width),
            lines as u32 * self.char_height,
        )
    }
}

impl Default for Font {
    fn default() -> Self {
        Self::new()
    }
} 