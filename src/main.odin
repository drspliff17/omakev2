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

	td := init_template_data(c)
	if td == nil do return
	defer free_template_data(td)

	fmt.println("TEST:")
	for t, i in td.data do fmt.printfln("%d - Path: %s", i, t.filepath)

	new, sub := parse_template_file(c, &td.data[2])
	defer delete(new)

	fmt.printfln(string(new[:]))
}
