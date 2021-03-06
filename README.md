Haste
=====
[![Build Status](https://travis-ci.org/valderman/haste-compiler.svg?branch=master)](https://travis-ci.org/valderman/haste-compiler.svg?branch=master)

A compiler to generate JavaScript code from Haskell.

It even has a [website](http://haste-lang.org) and a
[mailing list](https://groups.google.com/d/forum/haste-compiler).

Features
--------

* Seamless, type-safe single program framework for client-server communication
* Support for modern web technologies such as WebSockets, WebStorage and Canvas
* Simple JavaScript interoperability
* Generates small, fast programs
* Supports all GHC extensions except Template Haskell
* Uses standard Haskell libraries
* Cabal integration
* Simple, one-step build; no need for error prone Rube Goldberg machines of
  Vagrant, VirtualBox, GHC sources and other black magic
* Concurrency and MVars with Haste.Concurrent
* Unboxed arrays, ByteArrays, StableNames and other low level features
* Low-level DOM base library
* Easy integration with Google's Closure compiler
* Works on Windows, GNU/Linux and Mac OS X


Installation
------------

You have three options for getting Haste: installing from Hackage, from
Github or from one of the pre-built
[binary packages](http://haste-lang.org/#downloads).
In the first two cases, you need to add add Cabal's bin directory, usually
`~/.cabal/bin`, to your `$PATH` if you haven't already done so.
When installing from the Mac, Windows or generic Linux package, you may want
to add `path/to/haste-compiler/bin` to your `$PATH`.
The Debian package takes care of this automatically.

Then, installing the latest stable-ish version from cabal is easy:

    $ cabal install haste-compiler
    $ haste-boot

Building from Github source is equally easy. After checking out the source,
`cd` to the source tree and run:

    $ cabal install
    $ haste-boot --force --local

If you are having problems with the `haste-cabal` installed by `haste-boot`,
you can try building it from scratch and then passing the `--no-haste-cabal`
flag to `haste-boot`:

    $ git clone https://github.com/valderman/cabal.git
    $ cd cabal && git checkout haste-cabal
    $ cd Cabal && cabal install
    $ cd ../cabal-install && cabal install

When installing Haste from GitHub, you should probably run the test suite first,
to verify that everything is working. To do that, execute
`./runtests.sh` in the Haste root directory.  You may also run only a particular
test by executing `./runtests.sh NameOfTest`.  The test suite uses the `nodejs`
interpreter by default, but this may be modified by setting the `JS` environment
variable as such: `JS=other-js-interpreter ./runtests.sh`. Other JavaScript
interpreters may or may not work. `runtests.sh` isn’t downloaded when installing
from Hackage. You would have to download it from GitHub.

To build the patched Closure compiler used when compiling using `--opt-minify`,
get the Closure source, apply `patches/closure-argument-removal.patch` and
build it as you normally would. This is not usually necessary however,
as `haste-boot` fetches a pre-compiled Closure binary when run.

For more detailed build instructions, see `doc/building.md`.

Haste has been tested to work on Windows and OSX platforms, but is primarily
developed on GNU/Linux. As such, running on a GNU/Linux platform will likely
get you less bugs.


Usage
-----

To compile your Haskell program to a JavaScript blob ready to be included in an
HTML document or run using a command line interpreter:

    $ hastec myprog.hs

This is equivalent to calling ghc --make myprog.hs; Main.main will be called
as soon as the JS blob has finished loading.

You can pass the same flags to hastec as you'd normally pass to GHC:

    $ hastec -O2 -fglasgow-exts myprog.hs

Haste also has its own set of command line arguments. Invoke it with `--help`
to read more about them. In particular `--opt-all`, `--opt-minify`,
`--start` and `--with-js` should be fairly interesting.

If you want your package to compile with both Haste and, say, GHC, you might
want to use the CPP extension for conditional compilation. Haste defines the
preprocessor symbol `__HASTE__` in all modules it compiles. This symbol may
also be used to differentiate between Haste versions, since it is defined
as an integer representation of the current Haste version. Its format is
`MAJOR*10 000 + MINOR*100 + MICRO`. Version 1.2.3 would thus be represented as
10203, and 0.4.3 as 403.

Haste also comes with wrappers for cabal and ghc-pkg, named haste-cabal and
haste-pkg respectively. You can use them to install packages just as you would
with vanilla GHC and cabal:

    $ haste-cabal install mtl

Finally, you can interact with JavaScript code using the `Haste.Foreign`
module in the bundled `haste-lib` library.
See `doc/js-externals.txt` for more information about that.
This library also contains all sorts of functionality for DOM manipulation,
event handling, cooperative multitasking, canvas graphics, native JS
string manipulation, etc.

For more information on how Haste works, see
[the Haste Report](http://haste-lang.org/hastereport.pdf "Haste Report"),
though beware that parts of Haste may have changed quite a bit.

You should also have a look at the documentation and/or source code for
`haste-lib`, which resides in the `libraries/haste-lib` directory, and the
small programs in the `examples` directory, to get started.


Interfacing with JavaScript
---------------------------

When writing programs you will probably want to use some native JavaScript
in your program; bindings to native libraries, for instance.
The preferred way of doing this is the `Haste.Foreign` module:

    {-# LANGUAGE OverloadedStrings #-}
    import Haste.Foreign
    
    addTwo :: Int -> Int -> IO Int
    addTwo = ffi "(function(x, y) {return x + y;})"

The `ffi` function is a little bit safer than the GHC FFI in that it enforces
some type invariants on values returned from JS, and is more convenient.
Performance-wise, it is roughly as fast as the GHC FFI except for complex types
(lists, records, etc.) where it is an order of magnitude faster.

If you do not feel comfortable throwing out your entire legacy JavaScript
code base, you can export selected functions from your Haste program and call
them from JavaScript:

fun.hs:

    {-# LANGUAGE OverloadedStrings #-}
    import Haste.Foreign
    import Haste.Prim (toJSStr)

    fun :: Int -> String -> IO String
    fun n s = return $ "The number is " ++ show n ++ " and the string is " ++ s

    main = do
      export "fun" fun

legacy.js:

    function mymain() {
      console.log(Haste.fun(42, "hello"));
    }

...then compile with:

    $ hastec '--start=$HASTE_MAIN(); mymain();' --with-js=legacy.js fun.hs

`fun.hs` will export the function `fun` when its `main` function is run.
Our JavaScript obviously needs to run after that, so we create our "real" main
function in `legacy.js`. Finally, we tell the compiler to start the program by
first executing Haste's `main` function (the `$HASTE_MAIN` gets replaced by
whatever name the compiler chooses for the Haste `main`) and then executing
our own `mymain`.

The mechanics of `Haste.Foreign` are described in detail in this
[paper](http://haste-lang.org/ifl15.pdf).


Effortless type-safe client-server communication
------------------------------------------------

Using the framework from the `Haste.App` module hierarchy, you can easily write
web applications that communicate with a server without having to write a
single line of AJAX/WebSockets/whatever. Best of all: it's completely type
safe.

In essence, you write your web application as a single program - no more forced
separation of your client and server code. You then compile your program once
using Haste and once using GHC, and the two compilers will magically generate
client and server code respectively.

You will need to have the same libraries installed with both Haste and vanilla
GHC (unless you use conditional compilation to get around this).
`haste-compiler` comes bundled with all of `haste-lib`, so you
only need to concern yourself with this if you're using third party libraries.
You will also need a web server, to serve your HTML and JS files; the binary
generated by the native compilation pass only communicates with the client part
using WebSockets and does not serve any files on its own.

Examples of Haste.App in action is available in `examples/haste-app` and
`examples/chatbox`.

For more information about how exactly this works, see this
[paper](http://haste-lang.org/haskell14.pdf).


Base library and documentation
------------------------------

You can build your own set of docs for haste-lib by running
`cabal haddock` in the Haste base directory as with any other package.

Or you could just look at
[the online docs](http://haste-lang.org/docs/).


Libraries
---------

Haste is able to use standard Haskell libraries. However, some primitive
operations are still not implemented which means that any code making use
of them will give you a compiler warning, then die at runtime with an angry
error. Some libraries also depend on external C code - if you wish to use such
a library, you will need to port the C bits to JavaScript yourself (perhaps
using Emscripten) and link them into your program using `--with-js`.


Known issues
------------

* Not all GHC primops are implemented; if you encounter an unimplemented
  primop, please report it together with a small test case that demonstrates
  the problem.

* Template Haskell is still broken.

* Generated code is not compatible with the vanilla Closure compiler's
  `ADVANCED_OPTIMIZATIONS`, as it is not guaranteed to preserve
  `Function.length`.
  `haste-boot` bundles a compatibility patched version of Closure which does
  preserve this property. Invoking `hastec` with the `--opt-minify` option
  will use this patched version to minify the generated code with advanced
  optimizations.
