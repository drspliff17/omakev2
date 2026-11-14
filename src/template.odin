package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

@(private = "file")
Template :: struct {
	filepath:      string,
	name_override: string,
	keys:          []string,
}

Template_Data :: struct {
	data: []Template,
}

FileKeys :: distinct []string

// Returns allocated file keys
get_file_keys :: proc(f: os.File_Info) -> FileKeys {
	s := make([dynamic]string)
	defer delete(s)

	#partial switch f.type {
	case .Regular:
		bytes, err := os.read_entire_file_from_path(f.fullpath, context.allocator)
		if err != nil do fmt.panicf("Failed to read file: %s -> %v", f.fullpath, err)
		defer delete(bytes)

		data := string(bytes)
		i := 0

		for i < len(data) {
			if i + 1 < len(data) && data[i] == '{' && data[i + 1] == '{' {
				start := i + 2
				end := start

				for end + 1 < len(data) {
					if data[end] == '}' && data[end + 1] == '}' do break
					end += 1
				}

				if end + 1 < len(data) {
					key := strings.trim_space(data[start:end])

					if len(key) > 0 {
						found := false
						for existing in s {
							if existing == key {
								found = true
								break
							}
						}

						if !found do append(&s, strings.clone(key))
					}

					i = end + 2
					continue
				}
			}

			i += 1
		}

	case .Directory:
		fi, err := os.read_all_directory_by_path(f.fullpath, context.allocator)
		if err != nil do fmt.panicf("Failed to read directory: %s -> %v", f.fullpath, err)
		defer {
			for f in fi do os.file_info_delete(f, context.allocator)
			delete(fi)
		}

		for f in fi {
			k := get_file_keys(f)
			defer {
				for str in k do delete_string(str)
				delete(k)
			}

			for str in k {
				found := false
				for existing in s {
					if existing == str {
						found = true
						break
					}
				}

				if !found do append(&s, strings.clone(str))
			}
		}
	}

	return FileKeys(slice.clone(s[:]))
}

free_file_keys :: proc(f: FileKeys) {
	for k in f do delete_string(k)
	delete(f)
}

@(private = "file")
// Construct new Template, deep clones arguments, cleanup with free_template()
construct_template :: proc(filepath: string, keys: FileKeys) -> Template {
	t := Template {
		filepath = strings.clone(filepath),
		keys     = make([]string, len(keys)),
	}

	for k, i in keys do t.keys[i] = strings.clone(k)
	return t
}

@(private = "file")
// Frees allocated strings inside given Template
free_template :: proc(t: ^Template) {
	if len(t.filepath) > 0 do delete_string(t.filepath)
	if len(t.name_override) > 0 do delete_string(t.name_override)

	for k in t.keys do delete_string(k)
	if len(t.keys) > 0 do delete(t.keys)
}

@(private = "file")
// Construct top-level Template_Data for Config.template_dirs
construct_template_data :: proc(c: ^Config, td: ^Template_Data) -> (ok: bool) {
	t := make([dynamic]Template)
	defer delete(t)

	for tp in c.template_dirs {
		fi, err := os.read_all_directory_by_path(tp, context.allocator)
		if err != nil {
			fmt.eprintfln("Failed to read directory: %s -> %v", tp, err)
			continue
		}
		defer {
			for f in fi do os.file_info_delete(f, context.allocator)
			delete(fi)
		}
		for f in fi {
			keys := get_file_keys(f)
			defer free_file_keys(keys)
			template := construct_template(f.fullpath, keys)

			append(&t, template)
		}
	}

	td.data = make([]Template, len(t))
	l := copy(td.data, t[:])
	if l != len(t) {
		fmt.eprintfln("Failed to copy all Template bytes - Missing: %d", len(t) - l)
		return false
	}
	return true
}

key_used_in_template :: proc(key: string, td: ^Template_Data) -> bool {
	for t in td.data do for k in t.keys do if key == k do return true
	return false
}

key_in_config :: proc(key: string, c: ^Config) -> bool {
	for k in c.keys do if key == k do return true
	return false
}

init_template_data :: proc(c: ^Config) -> ^Template_Data {
	t := new(Template_Data)

	if !construct_template_data(c, t) {
		free(t)
		return nil
	}

	return t
}

free_template_data :: proc(td: ^Template_Data) {
	for &t in td.data do free_template(&t)
	delete(td.data)
	free(td)
}

// Parses given template entry, with given array of config keywords, returns the subbed file data in bytes
encode_template_file :: proc(
	c: ^Config,
	t: ^Template,
) -> (
	new_data: [dynamic]byte,
	was_sub: bool,
) {
	data, err := os.read_entire_file_from_path(t.filepath, context.allocator)
	if err != nil do fmt.panicf("Failed to read data from file: %s :: %v", t.filepath, err)
	defer delete(data, context.allocator)

	lines, lerr := strings.split(string(data), "\n")
	if lerr != nil do fmt.panicf("Failed to split file bytes: %s -> %v", t.filepath, lerr)
	defer delete(lines)

	for line in lines {
		new_line := line
		was_replaced := false

		for k in c.keys {
			keyF := strings.concatenate([]string{"{{", k, "}}"}, context.allocator)
			if strings.contains(line, keyF) {
				//TODO: Make way of getting current value associated with given key
				replaced, _ := strings.replace_all(line, keyF, "CHEESE")
				if was_replaced do delete_string(new_line)

				new_line = replaced
				was_replaced = true
				was_sub = true
			}
			delete_string(keyF)
		}

		if was_replaced {
			append(&new_data, new_line)
			delete_string(new_line)
		} else {
			append(&new_data, line)
		}

		append(&new_data, "\n")

	}

	return new_data, was_sub
}
