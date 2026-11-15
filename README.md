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

Any file inside a ``Template Directory`` is considered it's own
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
-l         -> List all available templates
-c         -> Count templates, has subcmd for variations
              Use 'omake -c h' for more information
```

### Key substitution

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

### Template Directories

You can also define additional ``Template Directories``:

```txt
template_dirs[0] = /home/you/someplace/templates
template_dirs[1] = /home/you/nowhere/templates
```

- *Note, default ``Template Directory`` will not be automatically loaded, if
``Config`` file exists. You can use 'omake -g' to generate a default file,
which includes your default ``Template Directory``*

- *Finally, you can also set ``enable_warnings``. This defaults to true in
the event of no ``Config`` file found, and included when a default is generated*
