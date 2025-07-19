use anyhow::Result;
use std::env;

mod framebuffer;
mod input;
mod pager;
mod font;
mod renderer;

#[cfg(feature = "desktop")]
mod sdl_renderer;

use renderer::Renderer;
use input::{InputDevice, InputEvent};
use pager::Pager;

fn main() -> Result<()> {
    println!("启动 Kindle 极简阅读器...");

    // 获取命令行参数中的文件路径
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("用法: {} <文本文件路径>", args[0]);
        eprintln!("示例: {} /mnt/us/documents/book.txt", args[0]);
        return Ok(());
    }

    let book_path = &args[1];
    println!("正在加载文件: {}", book_path);

    // 1. 初始化渲染器
    let mut renderer = Renderer::new()?;
    let (width, height) = renderer.resolution();
    println!("屏幕分辨率: {}x{}", width, height);

    // 2. 加载文本文件
    let text = std::fs::read_to_string(book_path)?;
    println!("文件大小: {} 字符", text.len());

    // 3. 创建分页器
    let pager = Pager::new(&text, width, height);
    println!("总页数: {}", pager.page_count());

    // 4. 检查是否是桌面模式
    if renderer.is_desktop() {
        // 桌面模式：使用 SDL2 事件循环
        run_desktop_mode(renderer, pager)?;
    } else {
        // 嵌入式模式：使用传统输入设备
        run_embedded_mode(renderer, pager)?;
    }

    Ok(())
}

#[cfg(feature = "desktop")]
fn run_desktop_mode(mut renderer: Renderer, pager: Pager) -> Result<()> {
    use sdl2::event::Event;
    use sdl2::keyboard::Keycode;

    println!("桌面模式：使用 SDL2 事件循环");
    
    // 获取 SDL2 事件泵 - 这里需要特殊处理
    // 由于我们的抽象层，我们需要通过某种方式访问 SDL2 的事件泵
    // 简化实现：使用键盘输入模拟
    
    let mut current_page = 0;
    
    // 这里我们暂时使用简化的桌面模式
    // 实际应该从 SDL2Renderer 中获取事件泵
    loop {
        println!("显示第 {} 页 (桌面模式)", current_page + 1);
        
        // 渲染当前页
        let page_bitmap = pager.render_page(current_page);
        renderer.draw_bitmap(&page_bitmap);
        renderer.refresh()?;
        
        // 简化的输入处理
        use std::io::{self, Write};
        
        print!("请输入命令 (n=下一页, p=上一页, q=退出): ");
        io::stdout().flush()?;
        
        let mut line = String::new();
        io::stdin().read_line(&mut line)?;
        
        match line.trim().to_lowercase().as_str() {
            "n" | "next" | " " | "" => {
                if current_page < pager.page_count() - 1 {
                    current_page += 1;
                    println!("下一页");
                } else {
                    println!("已是最后一页");
                }
            }
            "p" | "prev" | "b" | "back" => {
                if current_page > 0 {
                    current_page -= 1;
                    println!("上一页");
                } else {
                    println!("已是第一页");
                }
            }
            "q" | "quit" | "exit" => {
                println!("退出阅读器");
                break;
            }
            _ => {
                println!("未知命令");
            }
        }
    }
    
    Ok(())
}

#[cfg(not(feature = "desktop"))]
fn run_desktop_mode(_renderer: Renderer, _pager: Pager) -> Result<()> {
    anyhow::bail!("桌面模式在嵌入式版本中不可用")
}

fn run_embedded_mode(mut renderer: Renderer, pager: Pager) -> Result<()> {
    println!("嵌入式模式：使用传统输入设备");
    
    // 打开输入设备
    let mut input = InputDevice::auto_detect()?;
    println!("输入设备已就绪");

    // 主循环
    let mut current_page = 0;
    loop {
        println!("显示第 {} 页", current_page + 1);

        // 渲染当前页
        let page_bitmap = pager.render_page(current_page);

        // 写入渲染器
        renderer.draw_bitmap(&page_bitmap);

        // 刷新屏幕
        renderer.refresh()?;

        // 等待输入
        match input.wait_event()? {
            InputEvent::NextPage => {
                if current_page < pager.page_count() - 1 {
                    current_page += 1;
                    println!("下一页");
                } else {
                    println!("已是最后一页");
                }
            }
            InputEvent::PrevPage => {
                if current_page > 0 {
                    current_page -= 1;
                    println!("上一页");
                } else {
                    println!("已是第一页");
                }
            }
            InputEvent::Quit => {
                println!("退出阅读器");
                break;
            }
            InputEvent::Unknown => {
                // 忽略未知事件
            }
        }
    }
    
    Ok(())
}
