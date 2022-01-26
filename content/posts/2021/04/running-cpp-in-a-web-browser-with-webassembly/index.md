---
title: Running C++ in a Web Browser with WASM
description: A very basic intro to compiling and running C++ for the web.
date: 2021-04-25
draft: false
---

I recently started looking into compiling and running C++ for the web as a way to give some [old](https://github.com/tomcant/tic-tac-toe-ai)
[projects](https://github.com/tomcant/sudoku-solver) a much-needed makeover. In this post we'll look at some basic
examples of compiling C++ and running it in a web browser. <!--more-->

## The Emscripten Build Environment

We'll need the <a href="https://emscripten.org">Emscripten</a> SDK and accompanying tools to compile our code. The
[docs](https://emscripten.org/docs/getting_started/downloads.html) recommend installing them directly on our machine,
but I've never been much of a fan of that approach. Fortunately, there's an [officially supported Docker image](https://hub.docker.com/r/emscripten/emsdk)
we can use instead, so we'll prefix any commands with the following snippet:

```shell
docker run -v $(pwd):/src emscripten/emsdk:2.0.18 ...
```

At the time of writing, the latest version of Emscripten is `2.0.18`, so we'll target that specifically.

## Hello, WebAssembly

Let's start with the most basic example possible:

<div class="highlight-filename before">hello.cpp</div>

```cpp
#include <iostream>

int main() {
  std::cout << "Hello, WebAssembly" << std::endl;
}
```

Invoke the compiler as follows:

```shell
docker run -v $(pwd):/src emscripten/emsdk:2.0.18 \
  emcc hello.cpp -o hello.js
```

We expect this to generate two files:

- `hello.wasm` &ndash; a binary file to be executed in the browser
- `hello.js` &ndash; a script to load and execute the `.wasm`

These are the kind of files you add to `.gitignore` and build as part of CI/CD.

A simple `<script>` tag will be enough to run this example in a browser:

<div class="highlight-filename before">index.html</div>

```html
<script src="hello.js"></script>
```

Emscripten's default behaviour is to call `main()` and relay any output on `stdout` to the developer console, so if it
worked, you should see _Hello, WebAssembly_ when the page loads.

<div class="note note-info">
  <div class="note-title">
    Run the examples with Docker/Nginx
  </div>
  <div class="note-body">
    <p>
      The generated JavaScript loads the compiled binary with an XHR request, which means the example won't work by
      simply loading the HTML file in a browser &ndash; we need a local web server instead.
    </p>
    <p>
      An easy way to run the example on your <a href="http://localhost">localhost</a> is with the following command in
      the directory containing <code>index.html</code>:
    </p>
    <pre><code>docker run -v <span style="color:#007020;font-weight:bold">$(</span><span style="color:#007020">pwd</span><span style="color:#007020;font-weight:bold">)</span>:/usr/share/nginx/html -p 80:80 nginx</code></pre>
  </div>
</div>

## Beyond the Basics

By this point, we have all we need to run basic C++ in the browser :tada:, but in order to actually do anything useful
we need to be able to interact with the compiled binary beyond the initial page load. Typically, we want to define a
public interface of functions and/or classes for JavaScript to make use of.

Let's take the following C++ and see how to call `square()` in the browser:

<div class="highlight-filename before">square.cpp</div>

```cpp
extern "C" int square(int n) {
  return n * n;
}
```

We'll talk about `extern "C"` later. This time we want to call a function other than `main()`, so we need to be more
specific with the compiler:

```shell
docker run -v $(pwd):/src emscripten/emsdk:2.0.18 \
  emcc square.cpp -o square.js \
    -s "EXPORTED_FUNCTIONS=['_square']" \
    -s "EXPORTED_RUNTIME_METHODS=['cwrap']"
```

We specify the name of our function (with a preceding underscore) to prevent the compiler from removing it as part of
its "dead code elimination" process. We also told Emscripten to export `cwrap`, which is the JavaScript function we'll
use to actually call `square()`.

A typical setup in HTML could look like this:

<div class="highlight-filename before">index.html</div>

```html
<script>
  var Module = {
    onRuntimeInitialized: () => {
      const square = Module.cwrap('square', 'number', ['number']);
      console.log(`5 squared is ${square(5)}`); // 5 squared is 25
    }
  };
</script>

<script src="square.js"></script>
```

Here we set `Module.onRuntimeInitialized` to a callback function that Emscripten will execute when the binary file is
ready. We then wrap our C++ function and store it in `square` so we can call it later. The second and third arguments to
`cwrap()` describe the function signature: the return and parameter types, respectively. Finally, we call the wrapped
function just like any other JavaScript function call.

Both the examples in this post are running on this page, too, so if you open the developer console you should see
_5 squared is 25_ and _Hello, WebAssembly_. If you don't, then either I screwed up (entirely possible), or your browser
doesn't support WebAssembly yet (see [caniuse.com/wasm](https://caniuse.com/wasm)). In any case, here's an interactive
example:

<div id="demo">
  <input type="number" style="width: 4rem;">
  <button>Square</button>
  <span></span>
  <script>
    const input = document.querySelector('input');
    input.value = 1 + Math.floor(Math.random() * 100);
    var Module = {
      onRuntimeInitialized: () => {
        const square = Module.cwrap('square', 'number', ['number']);
        document.querySelector('#demo button').addEventListener('click', () => {
          document.querySelector('#demo span').innerHTML = `<code>${input.value} squared is ${square(input.value)}</code>`;
        });
        console.log(`5 squared is ${square(5)}`);
      }
    };
  </script>
  <script src="wasm.js"></script>
</div>

### A note about "name mangling"

If you're familiar with C/C++ then you might be wondering why we used `extern "C"` above. This tells the compiler to use
C naming conventions for our function and avoids the <a href="https://en.wikipedia.org/wiki/Name_mangling">name mangling</a>
process C++ uses to support function overloading. Without this, we'd need to know ahead of time how the compiler will
translate the name of our function so we can specify it during compilation &ndash; kind of a Catch-22!

## Conclusion

This post hardly scratches the surface of what's possible with WebAssembly, but hopefully these examples are enough to
get someone off the ground. In the future I'll write about how I'm using WebAssembly to bring some old projects to the
web.
