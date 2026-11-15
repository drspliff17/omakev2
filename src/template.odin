package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

@(private = "file")
Template :: struct {
	filepath: string,
	keys:     []string,
}

Template_Data :: struct {
	data:          []Template,
	name_override: string,
}

FileKeys :: distinct []string

valid_template_name :: proc(t: string, td: ^Template_Data) -> (idx: int, ok: bool) {
	for &x, i in td.data do if os.base(x.filepath) == t do return i, true
	return 0, false
}

is_ascii_alpha :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
}

is_key_char :: proc(ch: u8) -> bool {
	return is_ascii_alpha(ch) || (ch >= '0' && ch <= '9') || ch == '_'
}

@(private = "file")
// Resolve one complete $key or %special token. Returned strings are allocated
resolve_special_token :: proc(
	token: string,
	c: ^Config,
	ap: ^[dynamic]ArgumentPair,
	t: ^Template,
	td: ^Template_Data,
) -> (
	value: string,
	ok: bool,
) {
	if len(token) < 2 do return "", false

	switch token[0] {
	case '$':
		key := token[1:]
		if idx, found := key_in_arg_pair(key, ap); found {
			return strings.clone(ap[idx].value), true
		}
		return "", false

	case '%':
		special := strings.to_lower(token[1:])
		defer delete_string(special)

		switch special {
		case "b", "p":
			wd, err := os.get_working_directory(context.allocator)
			if err != nil do fmt.panicf("Failed get_working_directory() -> %v", err)
			defer delete_string(wd)
			if special == "p" do return strings.clone(wd), true
			return strings.clone(os.base(wd)), true

		case "d", "t", "dt":
			ts := time.now()
			switch special {
			case "d":
				b: [time.MIN_YYYY_DATE_LEN]u8
				return strings.clone(time.to_string_dd_mm_yyyy(ts, b[:])), true
			case "t":
				b: [time.MIN_HMS_LEN]u8
				return strings.clone(time.time_to_string_hms(ts, b[:])), true
			case "dt":
				db: [time.MIN_YYYY_DATE_LEN]u8
				tb: [time.MIN_HMS_LEN]u8
				d := time.to_string_dd_mm_yyyy(ts, db[:])
				time_text := time.time_to_string_hms(ts, tb[:])
				return fmt.aprintf("%s %s", d, time_text), true
			}

		case "n":
			if len(td.name_override) == 0 do return strings.clone(os.base(t.filepath)), true
			return strings.clone(td.name_override), true
		}
	}

	return "", false
}

@(private = "file")
// Expand $key references recursively before resolving any %special tokens.
// This allows config values to compose other config values, e.g. path = %p/$bin
// while bin = %n. Cyclic references are rejected.
expand_key_references :: proc(
	val: string,
	ap: ^[dynamic]ArgumentPair,
	key_stack: ^[dynamic]string,
) -> (
	value: string,
	ok: bool,
) {
	if len(val) == 0 do return strings.clone(""), true

	parts := make([dynamic]string)
	owned := make([dynamic]string)
	defer {
		for part in owned do delete_string(part)
		delete(owned)
		delete(parts)
	}

	i := 0
	literal_start := 0
	for i < len(val) {
		if val[i] != '$' {
			i += 1
			continue
		}

		token_end := i + 1
		key := ""
		if token_end < len(val) && val[token_end] == '{' {
			close := token_end + 1
			for close < len(val) && val[close] != '}' do close += 1
			if close >= len(val) || close == token_end + 1 do return "", false
			key = val[token_end + 1:close]
			token_end = close + 1
		} else {
			for token_end < len(val) && is_key_char(val[token_end]) do token_end += 1
			if token_end == i + 1 {
				i += 1
				continue
			}
			key = val[i + 1:token_end]
		}

		if i > literal_start do append(&parts, val[literal_start:i])

		for existing in key_stack^ {
			if existing == key do return "", false
		}

		idx, found := key_in_arg_pair(key, ap)
		if !found do return "", false

		append(key_stack, key)
		resolved, resolved_ok := expand_key_references(ap[idx].value, ap, key_stack)
		unordered_remove(key_stack, len(key_stack^) - 1)
		if !resolved_ok do return "", false

		append(&parts, resolved)
		append(&owned, resolved)

		i = token_end
		literal_start = i
	}

	if literal_start < len(val) do append(&parts, val[literal_start:])
	return strings.concatenate(parts[:], context.allocator), true
}

// Compose literal text and %special references after recursively expanding
// every $key reference. Returned strings are allocated.
evaluate_special_value :: proc(
	val: string,
	c: ^Config,
	ap: ^[dynamic]ArgumentPair,
	t: ^Template,
	td: ^Template_Data,
) -> (
	value: string,
	ok: bool,
) {
	key_stack := make([dynamic]string)
	defer delete(key_stack)

	expanded, expanded_ok := expand_key_references(val, ap, &key_stack)
	if !expanded_ok do return "", false
	defer delete_string(expanded)

	if len(expanded) == 0 do return strings.clone(""), true

	parts := make([dynamic]string)
	owned := make([dynamic]string)
	defer {
		for part in owned do delete_string(part)
		delete(owned)
		delete(parts)
	}

	i := 0
	literal_start := 0
	for i < len(expanded) {
		if expanded[i] != '%' {
			i += 1
			continue
		}

		token_end := i + 1
		for token_end < len(expanded) && is_ascii_alpha(expanded[token_end]) do token_end += 1
		if token_end == i + 1 {
			i += 1
			continue
		}

		if i > literal_start do append(&parts, expanded[literal_start:i])

		token := expanded[i:token_end]
		resolved, found := resolve_special_token(token, c, ap, t, td)
		if !found do return "", false

		append(&parts, resolved)
		append(&owned, resolved)

		i = token_end
		literal_start = i
	}

	if literal_start < len(expanded) do append(&parts, expanded[literal_start:])
	return strings.concatenate(parts[:], context.allocator), true
}

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
			for &f in fi do os.file_info_delete(f, context.allocator)
			delete(fi)
		}

		for &f in fi {
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

	for &k, i in keys do t.keys[i] = strings.clone(k)
	return t
}

@(private = "file")
// Frees allocated strings inside given Template
free_template :: proc(t: ^Template) {
	if len(t.filepath) > 0 do delete_string(t.filepath)

	for &k in t.keys do delete_string(k)
	if len(t.keys) > 0 do delete(t.keys)
}

@(private = "file")
// Construct top-level Template_Data for Config.template_dirs
construct_template_data :: proc(c: ^Config, td: ^Template_Data) -> (ok: bool) {
	t := make([dynamic]Template)
	defer delete(t)

	for &tp in c.template_dirs {
		fi, err := os.read_all_directory_by_path(tp, context.allocator)
		if err != nil {
			fmt.eprintfln("Failed to read directory: %s -> %v", tp, err)
			continue
		}
		defer {
			for &f in fi do os.file_info_delete(f, context.allocator)
			delete(fi)
		}
		for &f in fi {
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

key_value_in_config :: proc(key: string, c: ^Config) -> (idx: int, ok: bool) {
	for &k, i in c.keys do if key == k.name && len(k.value) > 0 do return i, true
	return 0, false
}

key_in_arg_pair :: proc(key: string, ap: ^[dynamic]ArgumentPair) -> (idx: int, ok: bool) {
	for &a, i in ap do if a.key == key do return i, true
	return 0, false
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
	if len(td.name_override) > 0 do delete_string(td.name_override)
	delete(td.data)
	free(td)
}

// Parses given template entry, with given array of config keywords, returns the subbed file data in bytes
encode_template_file :: proc(
	a: ^[dynamic]ArgumentPair,
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

		for p in a {
			keyF := strings.concatenate([]string{"{{", p.key, "}}"}, context.allocator)
			defer delete_string(keyF)

			if strings.contains(line, keyF) {
				replaced, _ := strings.replace_all(new_line, keyF, p.value)
				if was_replaced do delete_string(new_line)

				new_line = replaced
				was_replaced = true
				was_sub = true
			}
		}

		if was_replaced {
			append(&new_data, new_line)
			delete_string(new_line)
		} else do append(&new_data, line)

		append(&new_data, "\n")

	}

	return new_data, was_sub
}

@(private = "file")
encode_file_recursive :: proc(
	a: ^[dynamic]ArgumentPair,
	f: os.File_Info,
	output_path: string,
) -> bool {
	if os.exists(output_path) {
		fmt.eprintfln("Failed to create template. File already exists at %s", output_path)
		return false
	}

	#partial switch f.type {
	case .Regular:
		t := Template {
			filepath = f.fullpath,
		}

		data, _ := encode_template_file(a, &t)
		defer delete(data)

		if err := os.write_entire_file(output_path, data[:]); err != nil {
			fmt.eprintfln("Failed to write %s -> %v", output_path, err)
			return false
		}

	case .Directory:
		if err := os.make_directory_all(output_path); err != nil {
			fmt.eprintfln("Failed to create directory: %s -> %v", output_path, err)
			return false
		}

		fi, err := os.read_all_directory_by_path(f.fullpath, context.allocator)
		if err != nil {
			fmt.eprintfln("Failed to read directory: %s -> %v", f.fullpath, err)
			return false
		}
		defer {
			for &x in fi do os.file_info_delete(x, context.allocator)
			delete(fi)
		}

		for &x in fi {
			child_output, err := os.join_path({output_path, x.name}, context.allocator)
			if err != nil {
				fmt.eprintfln("Failed to construct output path: %v", err)
				return false
			}
			defer delete_string(child_output)
			if !encode_file_recursive(a, x, child_output) do return false
		}

	case:
		fmt.eprintfln("Invalid file type. Expected Regular || Directory, got: %v", f.type)
		return false
	}

	return true
}

// Encode given Template, using given ArgumentPair array
encode_validated_template :: proc(
	a: ^[dynamic]ArgumentPair,
	t: ^Template,
	override: string = "",
) -> bool {
	f, err := os.stat(t.filepath, context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to stat file: %s -> %v", t.filepath, err)
		return false
	}
	defer os.file_info_delete(f, context.allocator)

	wd, e := os.get_working_directory(context.allocator)
	if e != nil {
		fmt.eprintfln("Failed to get working directory: %v", e)
		return false
	}
	defer delete_string(wd)

	name := len(override) > 0 ? override : f.name
	output_path, oe := os.join_path({wd, name}, context.allocator)
	if oe != nil {
		fmt.eprintfln("Failed to construct output path: %v", oe)
		return false
	}
	defer delete_string(output_path)

	return encode_file_recursive(a, f, output_path)
}
