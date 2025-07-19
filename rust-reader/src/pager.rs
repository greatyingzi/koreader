use crate::font::Font;

pub struct Pager {
    text: String,
    pages: Vec<String>,
    font: Font,
    page_width: u32,
    page_height: u32,
}

impl Pager {
    pub fn new(text: &str, width: u32, height: u32) -> Self {
        let font = Font::new();
        let (char_width, char_height) = font.char_dimensions();
        
        // 计算每页可显示的字符数
        let chars_per_line = (width / char_width) as usize;
        let lines_per_page = (height / char_height) as usize;
        let chars_per_page = chars_per_line * lines_per_page;
        
        println!("分页参数: {}x{} 像素, {}x{} 字符/行, {} 行/页, {} 字符/页", 
                 width, height, chars_per_line, lines_per_page, lines_per_page, chars_per_page);
        
        let pages = Self::split_text_into_pages(text, chars_per_line, lines_per_page);
        
        Self {
            text: text.to_string(),
            pages,
            font,
            page_width: width,
            page_height: height,
        }
    }
    
    fn split_text_into_pages(text: &str, chars_per_line: usize, lines_per_page: usize) -> Vec<String> {
        let mut pages = Vec::new();
        let mut current_page = String::new();
        let mut current_line = String::new();
        let mut line_count = 0;
        
        for c in text.chars() {
            if c == '\n' {
                // 换行
                current_page.push_str(&current_line);
                current_page.push('\n');
                current_line.clear();
                line_count += 1;
                
                if line_count >= lines_per_page {
                    pages.push(current_page.clone());
                    current_page.clear();
                    line_count = 0;
                }
            } else if c == '\r' {
                // 忽略回车符
                continue;
            } else {
                current_line.push(c);
                
                // 检查是否需要自动换行
                if current_line.chars().count() >= chars_per_line {
                    current_page.push_str(&current_line);
                    current_page.push('\n');
                    current_line.clear();
                    line_count += 1;
                    
                    if line_count >= lines_per_page {
                        pages.push(current_page.clone());
                        current_page.clear();
                        line_count = 0;
                    }
                }
            }
        }
        
        // 添加最后一页
        if !current_line.is_empty() {
            current_page.push_str(&current_line);
        }
        
        if !current_page.is_empty() {
            pages.push(current_page);
        }
        
        // 确保至少有一页
        if pages.is_empty() {
            pages.push("(空文件)".to_string());
        }
        
        pages
    }
    
    pub fn page_count(&self) -> usize {
        self.pages.len()
    }
    
    pub fn render_page(&self, page_index: usize) -> Vec<u8> {
        if page_index >= self.pages.len() {
            return self.render_empty_page();
        }
        
        let page_text = &self.pages[page_index];
        let bitmap = self.font.render_text(page_text, self.page_width, self.page_height);
        
        // 添加页码信息
        self.add_page_info(bitmap, page_index)
    }
    
    fn render_empty_page(&self) -> Vec<u8> {
        let error_text = "页面不存在";
        self.font.render_text(error_text, self.page_width, self.page_height)
    }
    
    fn add_page_info(&self, mut bitmap: Vec<u8>, page_index: usize) -> Vec<u8> {
        // 在底部添加页码信息 (简化实现)
        let page_info = format!("第 {} 页 / 共 {} 页", page_index + 1, self.pages.len());
        
        // 计算页码信息的位置 (底部居中)
        let (char_width, char_height) = self.font.char_dimensions();
        let info_width = page_info.len() as u32 * char_width;
        let info_x = (self.page_width.saturating_sub(info_width)) / 2;
        let info_y = self.page_height.saturating_sub(char_height * 2); // 距离底部2行
        
        // 渲染页码信息到位图
        self.draw_text_at(&mut bitmap, &page_info, info_x, info_y);
        
        bitmap
    }
    
    fn draw_text_at(&self, bitmap: &mut [u8], text: &str, start_x: u32, start_y: u32) {
        let (char_width, _char_height) = self.font.char_dimensions();
        let mut x = start_x;
        
        for c in text.chars() {
            if let Some(glyph) = self.font.render_char(c) {
                self.draw_glyph_at(bitmap, &glyph, x, start_y);
                x += char_width;
                
                if x >= self.page_width {
                    break;
                }
            }
        }
    }
    
    fn draw_glyph_at(&self, bitmap: &mut [u8], glyph: &[u8; 8], start_x: u32, start_y: u32) {
        for (row, &byte) in glyph.iter().enumerate() {
            for col in 0..8 {
                if (byte >> col) & 1 == 1 {
                    let x = start_x + (7 - col) as u32;
                    let y = start_y + row as u32;
                    let offset = (y * self.page_width + x) as usize;
                    
                    if offset < bitmap.len() {
                        bitmap[offset] = 0x00; // 黑色像素
                    }
                }
            }
        }
    }
    
    pub fn get_page_text(&self, page_index: usize) -> Option<&str> {
        self.pages.get(page_index).map(|s| s.as_str())
    }
    
    pub fn search_text(&self, query: &str) -> Vec<usize> {
        let mut results = Vec::new();
        let query_lower = query.to_lowercase();
        
        for (index, page) in self.pages.iter().enumerate() {
            if page.to_lowercase().contains(&query_lower) {
                results.push(index);
            }
        }
        
        results
    }
} 