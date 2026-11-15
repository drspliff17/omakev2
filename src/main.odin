package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

ArgumentSource :: enum {
	PARAM,
	CONFIG,
}

ArgumentPair :: struct {
	key:    string,
	value:  string,
	source: ArgumentSource,
}

lazy_convert :: proc(a: ConfigKey) -> ArgumentPair {
	return ArgumentPair {
		key = strings.clone(a.name),
		value = strings.clone(a.value),
		source = .CONFIG,
	}
}

free_argument_pairs :: proc(ap: ^[dynamic]ArgumentPair) {
	for &a in ap^ {
		if len(a.key) > 0 do delete_string(a.key)
		if len(a.value) > 0 do delete_string(a.value)
	}
	delete(ap^)
}

print_help :: proc() {
	u, _ := os.user_home_dir(context.allocator)
	defer delete_string(u)
	h := `------------------------------
            omake
------------------------------
Usage:
omake [-h] [-d] [-g] [-l [name] ] [-c [opt] ]
[-n name] [-k name value] <template name>

-h | help
-g | gen                -> Generate default config

-d | default            -> View config key values
-l | list  [name]       -> View valid templates
-c | count [opt]        -> Use 'h' for subcmds

-n | name  <value>      -> Assign Template name
-k | key <name> <value> -> Define K/V Pair

Config:
Loaded automatically if file exists at:
%s/.config/omake/config

You can define default values to arbitrary key
names, for example:

keys[0].name = target
keys[0].value = src

keys[1].name = ....

Additionally, you can define multiple source paths for
templates. Note, if no config file exists, the below
path is created && used, by default:

template_dirs[0] = %s/.config/omake/templates
template_dirs[1] = .....

By default, if no file exists, warnings will be enabled.
If you would like them, be sure to add:

enable_warnings = true
`
	fmt.printfln(h, u, u)
}

main :: proc() {
	when ODIN_DEBUG {
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
	}

	ap := make([dynamic]ArgumentPair)
	defer free_argument_pairs(&ap)

	c := init_config()
	if c == nil do os.exit(1)
	defer free_config(c)

	for &ck in c.keys {
		if len(ck.name) == 0 || len(ck.value) == 0 do continue

		duplicate := false
		for existing in ap {
			if existing.key == ck.name && existing.value == ck.value {
				duplicate = true
				break
			}
		}
		if !duplicate do append(&ap, lazy_convert(ck))
	}

	td := init_template_data(c)
	if td == nil do os.exit(1)
	defer free_template_data(td)

	arg := os.args[1:]
	if len(arg) == 0 {
		print_help()
		return
	}

	template_name := ""

	for len(arg) > 0 {
		switch arg[0] {
		case "-h", "--help", "help":
			print_help()
			return

		case "-g", "--gen", "gen":
			if !generate_default_config() do os.exit(1)
			return

		case "-d", "--default", "default":
			p := get_config_path()
			defer delete_string(p)
			if !os.exists(p) {
				fmt.eprintfln(
					"Config file does not exist - keys cannot be assigned a default value.\nExpected file location: %s\nUse 'omake -h' for more information",
					p,
				)
				os.exit(1)
			}

			s := make([dynamic]string)
			defer {
				for x in s do delete_string(x)
				delete(s)
			}
			for &a in ap do if a.source == .CONFIG do append(&s, fmt.aprintf("%s = %s", a.key, a.value))
			if len(s) == 0 {
				fmt.printfln("No Keys with assigned Values in Config file")
				return
			} else {
				fmt.println("Keys with assigned default values:")
				for x in s do fmt.printfln(" %s", x)
				return
			}

		case "-l", "--list", "list":
			arg = arg[1:]
			if len(arg) == 0 {
				for &t in td.data do fmt.printfln("Name: %s\n Keys -> %v", os.base(t.filepath), t.keys)
				return
			}
			if idx, ok := valid_template_name(arg[0], td); !ok {
				fmt.eprintfln(
					"Invalid usage: expected either no arguments, or a valid template name",
				)
				os.exit(1)
			} else {
				fmt.printfln("Keys -> %v", td.data[idx].keys)
				return
			}

		case "-c", "--count", "count":
			arg = arg[1:]
			if len(arg) == 0 {
				fmt.printfln("Template Count: %d", len(td.data))
				return
			}

			switch arg[0] {
			case "h", "help":
				fmt.println(
					"Valid subcommands:\n" +
					" ck  -> Config Key Count\n" +
					" tk  -> Template Unique Key Count\n" +
					" ttk -> Template Total Key Count",
				)
				return

			case "ck":
				fmt.printfln("Config Key Count: %d", len(c.keys))
				return

			case "tk", "ttk":
				unique := arg[0] == "tk"
				keys := make([dynamic]string)
				defer delete(keys)

				for &t in td.data do for k in t.keys {
					if unique {
						if !slice.contains(keys[:], k) do append(&keys, k)
					} else do append(&keys, k)
				}

				fmt.printfln(
					"%s Key Count: %d",
					unique ? "Template Unique" : "Template Total",
					len(keys),
				)
				return

			case:
				fmt.eprintfln(
					"Unknown Subcommand: %s\nUse 'omake -c help' for more valid subcommands",
					arg[0],
				)
				os.exit(1)
			}

		case "-n", "--name", "name":
			arg = arg[1:]
			if len(arg) == 0 {
				fmt.eprintfln("Invalid usage: expected name to override template output")
				os.exit(1)
			}

			if len(td.name_override) > 0 do delete_string(td.name_override)
			td.name_override = strings.clone(arg[0])
			arg = arg[1:]

		case "-k", "--key", "key":
			arg = arg[1:]
			if len(arg) < 2 {
				fmt.eprintfln("Invalid usage: expected key and value")
				os.exit(1)
			}

			key := arg[0]
			value := arg[1]

			i := 0
			for i < len(ap) {
				if ap[i].key == key {
					if len(ap[i].key) > 0 do delete_string(ap[i].key)
					if len(ap[i].value) > 0 do delete_string(ap[i].value)
					unordered_remove(&ap, i)
				} else {
					i += 1
				}
			}

			append(
				&ap,
				ArgumentPair {
					key = strings.clone(key),
					value = strings.clone(value),
					source = .PARAM,
				},
			)
			arg = arg[2:]

		case:
			if len(template_name) > 0 {
				fmt.eprintfln("Unexpected argument: %s", arg[0])
				os.exit(1)
			}

			template_name = arg[0]
			arg = arg[1:]
		}
	}

	if idx, t_ok := valid_template_name(template_name, td); !t_ok {
		fmt.eprintfln(
			"[ERROR] Invalid template name: %s\nFound following templates:",
			template_name,
		)
		for &t in td.data do fmt.printfln("  %s", os.base(t.filepath))
		os.exit(1)
	} else {
		tf, tf_err := os.stat(td.data[idx].filepath, context.allocator)
		if tf_err != nil do fmt.panicf("Failed to stat template file: %s -> %v", td.data[idx].filepath, tf_err)
		defer os.file_info_delete(tf, context.allocator)

		template_keys := get_file_keys(tf)
		defer free_file_keys(template_keys)

		missing_keys := make([dynamic]string)
		defer delete(missing_keys)

		for &tk in template_keys do if idx, ok := key_in_arg_pair(tk, &ap); !ok do append(&missing_keys, tk)
		if len(missing_keys) > 0 {
			for m in missing_keys do fmt.eprintfln("Missing value for key: %s", m)
			os.exit(1)
		}

		for &a in ap {
			v, ok := evaluate_special_value(a.value, c, &ap, &td.data[idx], td)
			if !ok do continue
			if len(a.value) > 0 do delete_string(a.value)
			a.value = v
			fmt.printfln("TEST: Key %s got value -> %s from %v", a.key, a.value, a.source)
		}

		if !encode_validated_template(&ap, &td.data[idx], td.name_override) do os.exit(1)
		fmt.printfln(
			"Created %s",
			len(td.name_override) > 0 ? td.name_override : os.base(td.data[idx].filepath),
		)
	}
}
