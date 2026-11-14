package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"

ArgumentPair :: struct {
	key:   string,
	value: string,
}

print_help :: proc() {

}

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
	if c == nil do os.exit(1)
	defer free_config(c)

	td := init_template_data(c)
	if td == nil do os.exit(1)
	defer free_template_data(td)

	ap := make([dynamic]ArgumentPair)
	defer {
		for p in ap {
			if len(p.key) > 0 do delete_string(p.key)
			if len(p.value) > 0 do delete_string(p.value)
		}
		delete(ap)
	}

	arg := os.args[1:]
	if len(arg) == 0 {
		print_help()
		return
	}

	for len(arg) > 0 {
		switch arg[0] {
		case "-h", "--help", "help":
			print_help()
			return

		case "-l", "--list", "list":
			for t in td.data do fmt.printfln("Name: %s\n Keys -> %v", os.base(t.filepath), t.keys)
			return

		case "-c", "--count", "count":
			arg = arg[1:]
			if len(arg) == 0 {
				fmt.printfln("Template Count: %d", len(td.data))
				return
			}

			switch arg[0] {
			case "h":
				fmt.printfln(
					"Valid subcommands:\n ck  -> Config Key Count\n tk  -> Template Unique Key Count\n ttk -> Template Total Key Count",
				)
				return

			case "ck":
				fmt.printfln("Config Key Count: %d", len(c.keys))
				return

			case "tk", "ttk":
				unique := arg[0] == "tk"
				c := make([dynamic]string)
				defer delete(c)
				for t in td.data do for k in t.keys {
					if unique do if !slice.contains(c[:], k) do append(&c, k)
					else do append(&c, k)
				}
				fmt.printfln(
					"%s Key Count: %d",
					unique ? "Template Unique" : "Template Total",
					len(c),
				)
				return

			case:
				fmt.eprintfln(
					"Invalid subcommand. Valid:\n ck -> Config Key Count\n tk -> Template Unique Key Count\n ttk -> Template Total Key Count",
				)
				os.exit(1)
			}

		case "-k", "--key", "key":
			if len(arg) < 2 {
				fmt.eprintfln("Invalid usage: expected value to assign to key: %s", arg[0])
				return
			}

		//TODO:

		case:
			fmt.eprintfln("Unknown argument: %s", arg[0])
			os.exit(1)
		}
	}

	// for t, i in td.data do fmt.printfln("TEST:\n%v", td.data[i])
	// fmt.printfln("TEST:\n%v", td.data[3])
	// for t, i in td.data do fmt.printfln("%d - Path: %s", i, t.filepath)
	// new, sub := encode_template_file(c, &td.data[2])
	// defer delete(new)
	//
	// fmt.printfln(string(new[:]))
}
