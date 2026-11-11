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

// Parses given template entry, with given array of config keywords, returns the subbed file data in bytes
parse_template_file :: proc(c: ^Config, t: ^Template) -> (new_data: [dynamic]byte, was_sub: bool) {
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

@(private = "file")
get_file_keys :: proc(f: os.File_Info) -> []string {
	s := make([dynamic]string)
	defer delete(s)

	#partial switch f.type {
	case .Regular:
		bytes, err := os.read_entire_file_from_path(f.fullpath, context.allocator)
		if err != nil do fmt.panicf("Failed to read file: %s -> %v", f.fullpath, err)
		defer delete(bytes)

		lines, serr := strings.split(string(bytes), "\n")
		if serr != nil do fmt.panicf("Failed to split file bytes: %s -> %v", f.fullpath, serr)
		defer delete(lines)

		for l in lines {

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
			for str in k do append(&s, str)
		}

	case:
	}

	return slice.clone(s[:])
}

@(private = "file")
get_template_keys :: proc(t: ^Template) {

}

@(private = "file")
// Construct new Template, arguments are cloned, cleanup with free_template()
construct_template :: proc(filepath: string, keys: []string) -> Template {
	t := Template {
		filepath = strings.clone(filepath),
		keys     = slice.clone(keys),
	}

	return t
}

@(private = "file")
// Frees allocated strings inside given Template
free_template :: proc(t: ^Template) {
	if len(t.filepath) > 0 do delete_string(t.filepath)
	if len(t.name_override) > 0 do delete_string(t.name_override)
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
			//TODO: Get keys recursively used inside template
			append(&t, construct_template(f.fullpath, {}))
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
