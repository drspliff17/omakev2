package main

import "../../lib/kvp"
import "core:fmt"
import "core:os"

Config :: struct {
	keys:          []string,
	template_dirs: []string,
}

@(private = "file")
// Returns allocated string
get_config_path :: proc() -> string {
	h, e := os.user_home_dir(context.allocator)
	if e != nil do fmt.panicf("Failed to allocate user home path: %v", e)
	defer delete_string(h)

	when ODIN_DEBUG {
		c, err := os.join_path({h, ".config", "omake", "config2"}, context.allocator)
		if err != nil do fmt.panicf("Failed to allocate user config path: %v", err)
		return c
	} else {
		c, err := os.join_path({h, ".config", "omake", "config"}, context.allocator)
		if err != nil do fmt.panicf("Failed to allocate user config path: %v", err)
		return c
	}
}

@(private = "file")
// Returns allocated string
get_default_template_path :: proc() -> string {
	s := get_config_path()
	defer delete_string(s)

	c, e := os.join_path({s, "templates"}, context.allocator)
	if e != nil do fmt.panicf("Failed to allocate default template directory: %v", e)

	return c
}

@(private = "file")
// Returns new Config, must be freed using free_config()
get_default_config :: proc() -> ^Config {
	tp := get_default_template_path()
	c := new(Config)
	c.template_dirs = make([]string, 1)
	c.template_dirs[0] = tp
	return c
}

@(private = "file")
// Attempt to unmarshal config using kvp
load_config :: proc(p: ^kvp.Parser, c: ^Config, filepath: string) -> bool {
	if kvp.register_struct_keys(p, Config) do return false
	if kvp.read_bytes_into_parser(p, filepath) do return false
	if kvp.tokenize_bytes(p) do return false
	if kvp.unmarshal(p, c) do return false
	return true
}

@(private = "file")
validate_config :: proc(p: ^kvp.Parser, c: ^Config) -> bool {
	err := make([dynamic]string)
	defer delete(err)

	for k, i in c.keys do if len(k) == 0 do append(&err, fmt.aprintf("[ERROR] Invalid Key - Line: %d, expected atleast one character", i + 1))
	for t, i in c.template_dirs do if !os.exists(t) do append(&err, fmt.aprintf("[ERROR] Invalid template directory path - Line: %d", i + 1))

	if len(err) == 0 do return true

	for e in err do fmt.eprintfln(e)
	return false
}

// Constructor
init_config :: proc() -> ^Config {
	cp := get_config_path()
	defer delete_string(cp)

	if !os.exists(cp) {
		when ODIN_DEBUG do fmt.printfln("Using default configuration")
		return get_default_config()
	} else {
		c := new(Config)

		p := kvp.init_parser()
		defer kvp.free_parser(&p)

		when ODIN_DEBUG do fmt.printfln("Attempting to load config")
		if load_config(&p, c, cp) {
			if validate_config(&p, c) {
				when ODIN_DEBUG do fmt.printfln("Loaded config successfully")
				return c
			} else {
				when ODIN_DEBUG do fmt.printfln("Returning nil for config")
				free(c)
				fmt.eprintfln("[ABORTING]")
				return nil
			}
		} else {
			tk := kvp.get_cloned_token_array(&p)
			defer if len(tk) > 0 do delete(tk)

			err := kvp.get_cloned_error_array(&p)
			defer delete(err)

			l := len(err)
			assert(l > 0)

			fmt.eprintfln("[CONFIG ERRORS] %s", cp)
			for e in err {
				if e.line > 0 {
					fmt.eprintfln("\tLine %d: %v", e.line, e.type)
				} else if e.token_index >= len(tk) {
					fmt.eprintfln("\t%v", e.type)
				} else {
					t := tk[e.token_index]
					fmt.eprintfln(
						"\tToken: key = %s | val = %s | line = %d: %v",
						t.key,
						t.value,
						t.line,
						e.type,
					)
				}
			}

			when ODIN_DEBUG do fmt.printfln("Returning nil for config")
			free(c)
			fmt.eprintfln("[ABORTING]")
			return nil

		}
	}
}

// Free all allocated memory, owned by given ^Config
free_config :: proc(c: ^Config) {
	if len(c.keys) > 0 {
		for k in c.keys do if len(k) > 0 do delete_string(k)
		delete(c.keys)
	}

	if len(c.template_dirs) > 0 {
		for d in c.template_dirs do if len(d) > 0 do delete_string(d)
		delete(c.template_dirs)
	}

	free(c)
}
