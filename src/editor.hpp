#pragma once

#include "shared.hpp"
#include "filesystem.hpp"
#include "renderer.hpp"
#include "cursor.hpp" 
#include "buffer.hpp"
#include <string>

class Editor {
public:
	Editor() = default;
	~Editor() = default;

	void initialize(WindowHandle handle, const char* initial_path) {
		window_ = handle;
		root_path_ = initial_path; 
		#if defined(PLATFORM_MACOS)
			renderer_ = create_renderer(RenderBackend::Metal);
		#else
			renderer_ = create_renderer(RenderBackend::DirectX11);
		#endif

		if (renderer_) {
			if (!renderer_->initialize(window_, RenderConfig{})) {
				renderer_ = nullptr;
			}
		} else {
			printf("test");
		}

		current_buffer_ = new TextBuffer();
	}

	void handle_input_buffer(char input_char) 
	{
		current_buffer_->move_gap(cursor_.buffer_index);
		current_buffer_->insert(input_char);
		cursor_.buffer_index++;
		update_cursor_visuals();
	}

	void handle_backspace() {
		if (cursor_.buffer_index > 0) {
			current_buffer_->move_gap(cursor_.buffer_index);
			current_buffer_->backspace();
			cursor_.buffer_index--;
		}
	}

	void update()
	{
		if (!window_.is_valid() || !renderer_) return;
		renderer_->begin_frame();

		std::string view = current_buffer_->get_text();
		renderer_->draw_text(view, {20, 40}, 14.0f, {255, 255, 255, 255});   
		renderer_->draw_rect(cursor_.visual_pixel_pos, {12, 18}, {0, 255, 0, 122});
		renderer_->end_frame();
	}
private:
	  void update_cursor_visuals() {
        std::string full_text = current_buffer_->get_text();
        
        // 1. Calculate Line and Column
        u32 current_line = 0;
        u32 current_column = 0;
        size_t last_newline_idx = 0;

        for (size_t i = 0; i < cursor_.buffer_index; ++i) {
            if (full_text[i] == '\n') {
                current_line++;
                last_newline_idx = i + 1;
                current_column = 0;
            } else {
            	std::string line_text = full_text.substr(last_newline_idx, cursor_.buffer_index - last_newline_idx);
                current_column += renderer_->get_text_width(line_text, 24.0f);
            }
        }

        cursor_.line = current_line;
        cursor_.column = current_column;

        float32 line_height = 24.0f; 
        cursor_.visual_pixel_pos.y = line_height + (current_line * line_height);

        std::string line_text = full_text.substr(last_newline_idx, cursor_.buffer_index - last_newline_idx);
        cursor_.visual_pixel_pos.x = 24.0f + renderer_->get_text_width(line_text, 24.0f);
    }

	IRenderer* renderer_;
	std::string root_path_;
	WindowHandle window_;
	TextBuffer* current_buffer_;
	Cursor cursor_;
};