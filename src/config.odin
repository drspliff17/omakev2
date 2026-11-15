package main

import "../../lib/kvp"
import "core:fmt"
import "core:os"

ConfigKey :: struct {
	name:  string,
	value: string,
}

Config :: struct {
	keys:            []ConfigKey,
	template_dirs:   []string,
	enable_warnings: bool,
}

@(private = "file")
// Ensures default template directory exists && has been assigned to Config. Panics if it does not exist, and fails to be created
ensure_default_template_directory :: proc(c: ^Config) {
	tp := get_default_template_path()

	if !os.exists(tp) do if e := os.make_directory_all(tp); e != nil do fmt.panicf("Failed to create default template directory: %v - %s", e, tp)
	else do fmt.printfln("[INFO] Created default template directory: %s", tp)

	c.template_dirs = make([]string, 1)
	c.template_dirs[0] = tp
}

@(private = "file")
// Returns allocated string for config file path
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
// Returns allocated string for default template directory path
get_default_template_path :: proc() -> string {
	s := get_config_path()
	defer delete_string(s)

	c, e := os.join_path({os.dir(s), "templates"}, context.allocator)
	if e != nil do fmt.panicf("Failed to allocate default template directory: %v", e)

	return c
}

@(private = "file")
// Returns new Config, must be freed using free_config()
get_default_config :: proc() -> ^Config {
	c := new(Config)
	c.enable_warnings = true
	ensure_default_template_directory(c)
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
// Ensures all keys are valid, and that default template directory is applied to Config -> ensuring all template directories exist
// Prints any errors encountered, or warnings found in Config
validate_config :: proc(p: ^kvp.Parser, c: ^Config) -> bool {
	err := make([dynamic]string)
	defer {
		for e in err do delete_string(e)
		delete(err)
	}

	for k in c.keys {
		if len(k.name) == 0 do append(&err, fmt.aprintf("[ERROR] Invalid Key: expected atleast one character for key name"))
		if c.enable_warnings do if len(k.value) == 0 do fmt.printfln("[WARN] Key missing default value: %s", k.name)
	}

	if len(c.template_dirs) == 0 {
		if c.enable_warnings do fmt.eprintfln("[WARN] No template directories loaded, attempting to use default...")
		ensure_default_template_directory(c)
	} else {
		tk := kvp.get_cloned_token_array(p)
		defer if len(tk) > 0 do delete(tk)

		for t, i in c.template_dirs {

			if !os.exists(t) {
				l: int
				for token in tk do if token.value == t do l = token.line
				append(
					&err,
					fmt.aprintf(
						"[ERROR] Invalid template directory path, does not exist - Line: %d\n\t-> %s",
						l,
						t,
					),
				)
				continue
			}

			fi, e := os.stat(t, context.allocator)
			if e != nil do fmt.panicf("Failed to stat path: %s -> %v", t, e)
			defer os.file_info_delete(fi, context.allocator)

			if fi.type != .Directory {
				l: int
				for token in tk do if token.value == t do l = token.line
				append(
					&err,
					fmt.aprintf(
						"[ERROR] Invalid template directory path, not a directory - Line: %d\n\t-> %s",
						l,
						t,
					),
				)
			}

			if fi.size == 0 {
				l: int
				for token in tk do if token.value == t do l = token.line
				if c.enable_warnings do fmt.eprintfln("[WARN] Template directory empty - Line: %d\n\t-> %s", l, t)
			}

		}

	}

	if len(err) == 0 do return true
	for e in err do fmt.eprintfln(e)
	return false
}

// Constructor. If config file does not exist, returns get_default_config(). Else, attempts
// to load config file. Prints all errors if load &&||validation fails
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
				free_config(c)
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

// Attempts to create default config file
generate_default_config :: proc() -> (ok: bool) {
	p := get_config_path()
	defer delete_string(p)

	if os.exists(p) {
		fmt.printfln("[WARN] File already exists: %s\nAborting...", p)
		return true
	}

	c := get_default_config()
	defer free_config(c)

	s := fmt.aprintfln(
		"\ntemplate_dirs[0] = %s\n\nenable_warnings = %v",
		c.template_dirs[0],
		c.enable_warnings,
	)
	defer delete_string(s)

	if err := os.write_entire_file(p, s); err != nil {
		fmt.eprintfln("Failed to write default config file: %v", err)
		return false
	}

	fmt.printfln("Created Default Config -> %s", p)
	return true
}

// Free all allocated memory, owned by given ^Config
free_config :: proc(c: ^Config) {
	if len(c.keys) > 0 {
		for k in c.keys do if len(k.name) > 0 do delete_string(k.name)
		for k in c.keys do if len(k.value) > 0 do delete_string(k.value)
		delete(c.keys)
	}

	if len(c.template_dirs) > 0 {
		for d in c.template_dirs do if len(d) > 0 do delete_string(d)
		delete(c.template_dirs)
	}

	free(c)
}
