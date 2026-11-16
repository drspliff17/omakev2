# Small utility for templating files

## Config

``Config`` file is *not* required, however a default ``Template Directory``
*will* be created on first use.

Expected ``Config`` file location:

```bash
$HOME/.config/omake/config
```

**Default** ``Template Directory``:

```bash
$HOME/.config/omake/templates
```

Any file/directory inside a ``Template Directory`` is considered it's own
``Template``.

## Usage

```txt
omake [-n <v>] [-k <n> <v>] <template name>
```

***Arguments && Options***

```txt
-h         -> Print help message
-g         -> Generate default config

-n <v>     -> Override output clone name
-k <n> <v> -> Assign a value to a named key

-d         -> View config key values
-l [n]     -> List all available templates && their keys, or,
              display keys for a given template (by name)
-c         -> Count templates, has subcmd for variations
              Use 'omake -c h' for more information
```

## Install / Build

### Installation

#### Linux

- Download the [latest release](https://github.com/drspliff17/omakev2/releases/latest)

Add to ``$PATH``

#### Other OS

- *Must build from source, see below*

### Build

- Requires [Odin Compiler](https://github.com/odin-lang/Odin)

Clone repo, ``cd`` into directory, and run:

```bash
odin build src -out:omakev2
```

Add to ``$PATH``

### Basic Key Substitution

Any ``Template`` file can contain keys, which are denoted by:

```txt
{{key_name}}
```

Then, you can either provide values for used keys on execution:

```bash
omake -k key_name "some key value" template_name
```

Or - you can define default values, to arbitrary key names, inside
your ``Config`` file:

```txt
keys[0].name = key_name
keys[0].value = some key value

keys[1].name = ......
```

- *Note, values assigned with the '-k' flag take precedence over ``Config`` values*

Using the **above example execution**, a template text file containing:

```txt
Here is some text, replaced with {{key_name}}
```

Would output:

```txt
Here is some text, replaced with some key value
```

### Advanced Key Substitution

You can additionally make use of value formatting. There are two types of formatting:

```txt
$name -> Key Reference
%x    -> Format Flag
```

- *Note, These types may be nested, but may **not** be cyclic in nature. Value
formatting may also be used when assigning value to '-n' argument*

A ``Key Reference`` simply inserts the corresponding value of the key ``name`` given.
The following ``Format Flags`` are available:

```txt
%d  -> Date (DD-MM-YYYY)
%t  -> Time (HH-MM-SS)
%dt -> DateTime (DD-MM-YYYY HH-MM-SS)
%n  -> Template Name / Name Override
%b  -> Base of Working Directory
%p  -> Full Working Directory
```

- *Note, if you would like to join multiple values, without a separating
character, you can use the following ``${key_name}`` syntax, instead
of ``$key_name``*

**Example ``Config``:**

```txt
keys[0].name = target
keys[0].value = src

keys[1].name = bin
keys[1].value = %n

keys[2].name = path
keys[2].value = %p/$bin
```

**Example ``Template``:**

```bash
# ~/.config/omake/templates/compile
odin build {{target}} -out "{{bin}}" || exit 1
[[ ! -e "~/.local/bin/{{bin}}" ]] &&  ln -s "{{path}}" "~/.local/bin/{{bin}}"
```

**Command:**

```bash
# ~/dev/Odin >
omake -n something compile
```

- *Note, just as with basic key subbing, '-k' arguments will overwrite config
defined defaults. Format flags && Key refs may be used here, although you may
have to wrap the key ref in single-quotes*

**Output:**

```bash
# ~/dev/Odin/something
odin build src -out "something" || exit 1
[[ ! -e "~/.local/bin/something" ]] &&  ln -s "~/dev/Odin/something" "~/.local/bin/something"
```

### Template Directories

You can also define additional ``Template Directories``:

```txt
template_dirs[0] = /home/you/someplace/templates
template_dirs[1] = ......
```

- *Note, default ``Template Directory`` will not be automatically loaded, if
``Config`` file exists. You can use 'omake -g' to generate a default file,
which includes your default ``Template Directory``*

- *Finally, you can also set ``enable_warnings``. This defaults to true in
the event of no ``Config`` file found, and is included when a default is generated*
