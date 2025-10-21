package editor

import "core:fmt"

//  The process of running code PROTOTYPE
// CTRL-I

// import os "core:os/os2"
// os.Process; {
//      r, w, _ := os.pipe()
//      defer os.close(w)

//      p, _ = os.process_start({
//        command = {"node", "j.js"},
//        stdout = w,
//      })
//    }

// 1. Find the path of the compiler /etc/ C:/ProgramFiles
// 2. Run the compiler: Node

// ----
// 3.1 give it a file.

prototype_run :: proc() {
	fmt.println("PROTOTYPE")
}
