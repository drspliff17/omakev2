package main

import "core:fmt"
import "core:mem"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("%v allocations not feed:\n", len(track.allocation_map))
			for _, entry in track.allocation_map do fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		} else do fmt.println("TEST: No unfreed allocations")

		if len(track.bad_free_array) > 0 {
			fmt.eprintf("%v incorrect free:\n", len(track.bad_free_array))
			for entry in track.bad_free_array do fmt.eprintf("- %v bytes @ %v\n", entry.memory, entry.location)
		} else do fmt.println("TEST: No bad free")

		mem.tracking_allocator_destroy(&track)
	}

	c := init_config()
	if c == nil do return
	defer free_config(c)
}
