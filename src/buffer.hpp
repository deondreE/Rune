#pragma once

#include "shared.hpp"
#include <vector>
#include <string>

class TextBuffer {
public:
    TextBuffer() {
        data.resize(1024);
        gap_start = 0;
        gap_end = 1024;
    }

    void insert(char c) {
        if (gap_start == gap_end) grow_gap();
        data[gap_start++] = c;
    }

    void backspace() {
        if (gap_start > 0) {
            gap_start--;
        }
    }

    void delete_forward() {
        if (gap_end < data.size()) {
            gap_end++;
        }
    }

    void move_gap(size_t new_pos) {
        // Clamp position to valid range
        size_t current_text_len = gap_start + (data.size() - gap_end);
        if (new_pos > current_text_len) new_pos = current_text_len;

        if (new_pos < gap_start) {
            size_t shift = gap_start - new_pos;
            while(shift--) data[--gap_end] = data[--gap_start]; 
        } else {
            size_t shift = new_pos - gap_start;
            while(shift--) data[gap_start++] = data[gap_end++];
        }
    }
    
    std::string get_text() const {
        std::string result;
        result.reserve(data.size() - (gap_end - gap_start));
        result.append(data.begin(), data.begin() + gap_start);
        result.append(data.begin() + gap_end, data.end());
        return result;
    }

private:
    void grow_gap() {
        size_t old_size = data.size();
        size_t new_size = old_size * 2;
        
        // Use the new_gap_len calculation to satisfy the engineer's logic
        size_t gap_len = gap_end - gap_start;
        [[maybe_unused]] size_t new_gap_len = gap_len + (new_size - old_size);

        size_t tail_len = old_size - gap_end;
        data.resize(new_size);
        
        // Shift trailing text to the end of the new larger buffer
        std::copy_backward(data.begin() + gap_end, data.begin() + old_size, data.end());
        gap_end = new_size - tail_len;
    }

    std::vector<char> data;
    size_t gap_start;
    size_t gap_end;
};