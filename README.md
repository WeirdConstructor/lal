LAL - Lua Lisp/Scheme Compiler
==============================

This project is the implementation of a Compiler for a Scheme like dialect of Lisp
that compiles to Lua and is itself written in Lua.

The project is developed mainly using Lua 5.3, but compatibility with Lua 5.2
is tested irregularly. Compatibility with Lua 5.2 is a feature that is supported.

Getting Started
---------------

Either use `git clone` or download the tar ball from http://github.com/weirdconstructor/lal


    ~/$ git clone git@github.com:weirdconstructor/lal.git
    ~/$ cd lal
    ./lal$ ln -s . lal
    ./lal$ lua repl.lua
    > (displayln "Hello World!")
    Hello World!
    => "Hello World!"
    >

And if you are eager to see the under the hood generated Lua:

    ./lal$ lua repl.lua -p
    > (displayln "Hello World!")
    CODE[if (os.getenv("LALRT_LIB")) then package.path = package.path .. ";"
    .. os.getenv("LALRT_LIB") .. '\\lal\\?.lua'; end;
    local _ENV = { _lal_lua_base_ENV = _ENV, _lal_lua_base_pairs = pairs };
    for k, v in _lal_lua_base_pairs(_lal_lua_base_ENV) do
    _ENV["_lal_lua_base_" .. k] = v end;

    return _ENV]
    CODE[local _lal_req1 = _lal_lua_base_require 'lal.lang.builtins';
    local strip_kw = _lal_req1["strip-kw"];
    local strip_sym = _lal_req1["strip-sym"];
    local displayln = _lal_req1["displayln"];
    --[[stdin:1]]
    return displayln("Hello World!");
    --[[stdin:1]]
    ]
    Hello World!
    => "Hello World!"
    >

To run the test suite do:

    ./lal$ mkdir lalTest
    ./lal$ lua lalTest.lua

State of the project
--------------------

Currently (2016-12-16) the compiler has been in development for roughly 8 months.
The implementation of the compiler itself is rather stable by now. Most of the
functionality is covered by the test suite in `lalTest.lua`.

The direct execution by Lua (version 5.3) has not been used heavily, because
there is _LALRT_ another project I use to execute Lua (and LAL). It's a runtime
written in C++ which embeds Lua and provides things like an integrated HTTP server,
TCP/UDP communication, serial communications and a high level Qt GUI. It's currently
heavy in development and not yet released or ready for public use.
LAL itself however is useful enough to be provided separately.

Reference
---------

For a reference about the syntax, see `doc/lal_reference.mkd`.

About the Lua Implementation
----------------------------

There are a few notes to make about the way LAL is compiled to Lua.
All LAL lists are directly converted and represented as Lua tables.
This means, you basically work with Lua tables. While this has obvious
performance benefits compared to using tables only as `cons` pairs to
form a linked list. It also comes with all the warts that Lua tables
have. First and probably the biggest one is, that you can not put a `nil`
into the list. It will just make the list end at that index.
This is probably the ugliest wart. The LAL parser internally replaces
`nil` with some sentinel value, but once it left the compiler and is
transformed into Lua code, you will have the Lua `nil` in your hands.

Next, tables also act as associative maps, which sometimes leads to confusing
results. LAL tries to hide that fact, but you will probably still stumble upon
this fact down the road.

Symbols are represented as Lua strings. This is done because Lua internalizes all
strings, so that a string comparison is essentially an integer comparison.
LAL represents Symbols as Lua strings that start with the character `"\xFE;"`
character number `254`. And keywords start with `"\xFD;"` (`253`).
Bear this in mind, if you get surprising results from
procedures like `(write ...)`. It also means, that if you write
`(display "\xFE;foobar")` you will get a compile time error, because LAL can't
find the symbol `foobar` (in case you didn't `define` it).

Keywords are a bit special, as they are translated to Lua strings without
prefix by the code generator when they are used as map keys.

It is a bit painful and ugly, but bear in mind that LAL comes with clear benefits
on the performance side compared to a full blown interpreter implemented in Lua.
Such an interpreter would need to represent Scheme `cons` pairs and lists as linked
lists of those pairs. That poses a big burden on the Lua garbage collector, and
handling those lists would be quite slow too. On top of that, interaction with
Lua code becomes difficult, as you would need to transform the linked
list into a Lua table first. And then you still have to worry about the `nil` holes.

About Lua and Lisp
------------------

When I started this project I wondered whether other languages would be
a good target too. But Lua actually turned out to be quite Lisp compatible
with regard to some of it's language features:

* Block scope allowed easy implementation of `let`.
  Compare this with Python, which does not have block scope. And in Python
  it's really hard, if not impossible, to implement it. Especially if you
  want your bindings being collected by the GC after the block scope is
  exited. In Python you would need to delete the renamed variables explicitly.
  If you look at JavaScript, only the recent version ES6 with `let` would
  allow for similar semantics.
* `lambda` maps trivially to Lua's anonymous functions. On top of that,
  Lua's closure semantics map perfectly too. In comparison to Python, which
  actually does not have anonymous functions, and capturing a binding is
  especially hard if not impossible.
* Lua's `math` library lends itself good to implement most semantics of
  Schemes numbers. While it does not directly provide ratios or complex numbers,
  the functions for integers and floating point math are all there.
* Due to Lua strings being interned and comparisons becoming an integer
  comparison they lend themselves perfectly for representing symbols.
  But to distinguish symbols and strings syntactically I needed to introduce
  the `"\xFE;"` and `"\xFD;"` prefixes for symbols and keywords.

Overall it was a breeze to implement this compiler. The only minor roadblock
were the array _hole_ semantics of Lua's tables. You can't get around the fact
that iterations stop at the first `nil`. I partially worked around this in
the parser by introducing a special LAL `nil` sentinel value, that is translated
to Lua's `nil` upon code generation. 

### A small Python rant

Midways I tried to shift my focus to Python, and implemented the LAL language
partially in Python with a Python code generator. Python has to many quirks that
make it uncomfortable for someone like me to use. I am used to the more functional
approach to programming, and Python makes that really hard to do. Overall Python
turned out so brain damaged and anal to use, that I just stopped and instead focused
on Lua and _LALRT_. _LALRT_ is my swiss army knife, it's my easily distributable
runtime environment for executing LAL applications.
It's a bit of a bummer to have to abandon the huge Python library ecosystem,
but the language is just unbearably inflexible to use for me.

License
-------

This source code is published under the MIT License. See lal.lua or LICENSE
file for the complete copyright notice.
