+++
title = "Laissez-Faire Errors"
date = 2026-05-27T21:30:00+08:00

[taxonomies]
tags = ["rust","blogging","error-handling","idiomatic"]
+++

# `std::error` 
Errors in Rust are unique in that they can be handled in so many ways. This can be confusing and seem tedious at first, but there are advantages to being able to choose to `panic!` when an `error` is reached, or extending your own errors in  such a way as to add context-specific information. [Or you can choose to simply `unwrap()` when an error is reached](https://blog.cloudflare.com/18-november-2025-outage/#memory-preallocation).  I am personally fond of creating errors using a custom `enum` and adding them as they are needed. Hence the title, *laissez-faire* errors. 
<!-- more -->
Errors in Rust are handled with the `Result` `enum`, and specifically as `Result<T,E>`, where `T` is a generic for the expected return type, an `i32` for example, and `E` is an error type, such as `std::io::Error` for example.

## errors --help
There are three main ways to handle a `Result<T,E>`:
1) **Ignore it**: use an `unwrap()` - which is the quick and dirty way of handling errors, or rather not handling them and assuming there never will be, or if there are errors, that a `panic!` is what you want to see. This is the least idiomatic method for production Rust.
2) **Explicitly**: Use a `match` statement against the `Result` `enum` itself, and do something with the `Error` variant manually. Viable but a headache in anything larger than a toy sized program. 
3) **Propagate:** Use the `?` operator and ensure that your methods are themselves returning the `Result` `enum`, and then at some point handle the error itself, as it bubbles up through your program's abstractions. This is the most idiomatic approach for production Rust, and simply extracts or unwraps (safely this time) the value if it's `Ok`, and if it is an error, returns the error for the function and terminates running the remaining function.
### errors --run --examples
Let's make a function that returns a `Result<T,E>`, and then use it for our examples. In this case it will take a parameter `input: i32` and check if it is divisible by two, returning the value if valid and an error if it is not (odd numbers cause errors). Why? Because it's the simplest example I could think of to illustrate the concepts I want to focus on for this example. Keep in mind these principles will remain the same regardless of the complexity of a function, we are focused on the return type and handling errors. 
```rust
pub fn divisible_by_two(input: i32) -> Result<i32, LaissezError> {
	// use the modulus here to check for remainder
	match input % 2 {
		0 => Ok(input),
		_ => Err(LaissezError::NotEven)
	}
}
```
Note that for this example we are going to implement our own error type, which is part of my goal of this project, to show *how ergonomic error handling is* with vanilla Rust.

**Our error `enum`:**
```rust
#[derive(Debug)]
pub enum LaissezError {  
	NotEven,  
}
```
And now we have a handy `enum` for our errors. As I'll show later, we can simply grow our error variants as our code base grows. Hence the name `LaissezError`, let the actual code base's error needs decide what is included here. I have added a `debug` derive for now, as it's necessary to derive your error `enum` for debugging to use it, and later we will add a `Display` implementation for the formatting info about the error.
#### `unwrap()`
The first and most reckless way to handle a `Result` is to call `unwrap()`. I'll illustrate this with a valid value, `4`, and an invalid value `3`. 

This first value could be dropped anywhere and be safe to use:
```rust
// this value will unwrap into the `Ok` variant and be safe to use later
let value1 = divisible_by_two(4).unwrap();
```

Note the lurking danger. This gives the impression that `divisible_by_two` is easy to anticipate and therefore can be assumed to succeed. But if that is the case, why would the author of the function even include a `Result` as the return type? Generally speaking using the `unwrap()` is only justified in things like *unit tests*, where the value is expected to be the `T` type, and is usually set a few lines before. But what happens if you run the code below?
```rust
// this will unwrap the `Result` but because it is the `Err` variant it will panic
let value2 = divisible_by_two(3).unwrap();
```

This will `panic` and return:
```bash
thread 'main' (824531) panicked at {file_name}.rs:{line}:{column}:
called `Result::unwrap()` on an `Err` value: NotEven
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

And this is not ideal. Note that a `panic` will [kill](https://doc.rust-lang.org/std/macro.panic.html) the currently running program. Unless that is the desired effect (which it rarely is), this should not be the go to for error handling. 

#### Explicit `match`
The next best way to handle the `Result` variants, is to match them. This may well be the best solution, depending on the context:
```rust
let value = match divisible_by_two(3) {
	Ok(value) => value,
	Err(err) => {
		// do something with the error like default to 0
		println!("{err}");
		0
	} 
}
```

Notice that this function handles the error in the moment the `divisible_by_two()` function returns. You could elect to substitute a value if the value is not divisible by two, or still opt to manually invoke a `panic!`, or any other of a number of options that would make sense in the context of the code base being used. Oftentimes it may be helpful to output the error, let's add a `fmt` block for the error `enum`:
```rust
impl std::fmt::Display for LaissezError {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		match self {
			Self::NotEven => write!(f, "The number is not even!")
		}
	}
}
```

Rust makes it very easy to format errors. Now we can try using a match statement. To keep in line with the first example, we'll convert the `i32` to `string` as well, so we can still assign the match return to a single variable:
```rust
fn main() {
        let value = match divisible_by_two(3) {
                Ok(val) => val.to_string(),
                Err(err) => err.to_string()
        };
        println!("{value}");
}
```
Running this you should now see:
```bash
The number is not even!
```

Which only outputs because we ran the `println!` macro. Notice that the program never has the opportunity to panic anymore. Instead we explicitly handle the error when it's encountered. Depending on the context of where the error is being returned, using a `match` statement and having some predetermined response to handle the `Err` variant, you could a number of actions, such as returning a default value or again, still panicking the program, perhaps with additional information about the error. 

We should go a step further and implement the `std::error::Error` for our error:
```rust
impl std::error::Error for LaissezError {}
```
#### Propagating with `?` 
More often than not the context of where the error is first being returned isn't the ideal location to handle errors. Ideally errors are being handled explicitly, such as above with a `match` statement, in as few places as possible. Thus it becomes necessary to *propagate*, or pass the error up, the layers of your application to where it will be processed and used. Luckily doing is very straightforward:
```rust
fn main() -> Result<(),LaissezError> {
	let value = divisible_by_two(3)?;
	println!("{value}");

	Ok(())
}
```

Note that in this case `main()` is modified to return `()` - [unit](https://doc.rust-lang.org/std/primitive.unit.html) or `LaissezError`. When `main` exits with an error, Rust prints the error using its `Debug` representation:
```bash
Error: NotEven
```

It's worth noting that propagation is very powerful in handling errors. Again the nature of propagating the error through layers of the application helps ensure their `Result` can be handled in the layer above. Clippy will also not let you propagate an error without fixing your function signature, note that leaving main to return `()` only will result in this error when trying to use the `?` operator to unwrap the value:
```bash
error[E0277]: the `?` operator can only be used in a function that returns `Result` or `Option` (or another type that implements `FromResidual`)
 --> {file}.rs:3:33
  |
2 | fn main() {
  | --------- this function should return `Result` or `Option` to accept `?`
3 |     let value = divisible_by_two(3)?;
  |                                    ^ cannot use the `?` operator in a function that returns `()`
  |
help: consider adding return type
  |
2 | fn main() -> Result<(), Box<dyn std::error::Error>> {
  |           +++++++++++++++++++++++++++++++++++++++++
```

Note that we do not want to return an `std::error::Error`, or rather can't as it is a trait, implemented by errors. But we could extend our `enum` to be able to come *from* another error type.
### `From Error`
We can easily wrap another error type, such as the `std::num::ParseIntError` in our `LaissezError`, as we can then try to parse `i32` from a `&str` and use our error `enum` to handle it when it goes wrong! To do so we should first add a new variant:

```rust
#[derive(Debug)]
pub enum LaissezError {  
	NotEven,
	ParseInt(std::num::ParseIntError)
}
```

Then we can use a `From` block to do the wrapping:
```rust
impl From<std::num::ParseIntError> for LaissezError {
    fn from(error: std::num::ParseIntError) -> Self {
        Self::ParseInt(error)
    }
}
```

And now if we extend our program with a function to parse the number from a `&str`, can then check if it's divisible by 2 directly inside the `parse_and_check` function we have:
```rust
pub fn parse_and_check(input: &str) -> Result<i32, LaissezError> {
    let number = input.parse::<i32>()?;
    divisible_by_two(number)
}
```

So a few things to note, our `Result` is returning `i32`, same as the `divisible_by_two`, and our error is the same, our `LaissezError`! So now there is the possibility for our code to return two separate error variants. However we do not need to update `main` as it will know what to do for either variant of our error! 

*note on generics*: This post isn't about *generics*. but above we have used `parse::<i32>()`, which is necessary as `parse` is implemented for multiple primitive types, and the function needs to know the type to function properly. This is a bit outside the scope of this post, but generics are something I plan on exploring more later on and worth noting here. 

In the `parse_and_check()` function above, the line:
```rust
   let number = input.parse::<i32>()?;
```

Will return `Result<i32, std::num::ParseIntError>`, and thanks to our `From` block, we are able to wrap that error in our `LaissezFaire` error. We can also update our `fmt` block to reflect that is error is a wrapped error:
```rust
impl std::fmt::Display for LaissezError {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		match self {
			Self::NotEven => write!(f, "The number is not even!"),
			Self::ParseInt(error) => write!(f,"failed to parse value, {}", error)
		}
	}
}
```

Note that you can choose to use the wrapped error or discard it. I have chosen to output my own message followed by the `ParseIntError` message from its own `fmt`:
```bash
Error: ParseInt(ParseIntError { kind: InvalidDigit })
```

And now we have added a new error variant to our `enum`. We didn't write it until we needed it, and thanks to Rust's *compiler* we know that we will be able to successfully wrap the `std` error. 

## Laissez-Faire errors
So the goal of this post was to give an introduction to writing your own errors, which we have covered; but it is also to discuss the philosophy of error writing. I coin the term *Laissez-Faire errors* based on the term [Laissez-Faire](https://en.wikipedia.org/wiki/Laissez-faire), commonly used to refer to any economic system where people can trade freely, when the *need* arises. Here though Laissez-Faire style error handling is referring to when to create new errors: when they're needed. 

It may be a bit of a subtle point but I would originally get bogged down with error handling in some of my first projects with Rust, and wind up writing an enormous `enum` with errors for every potential error that may arise. The result was a finished project, where I saw a lot of the enums go unused. If the `enum` wasn't used often, that isn't a big issue, but imagine if we extended the `LaissezError` `enum` to have 10 variants based on how we imagined using it at first, for issues we anticipated *might* come up:
```rust
#[derive(Debug)]
pub enum LaissezError {  
	NotEven,
	ParseInt(std::num::ParseIntError),
	Zero,
	IO(std::io::Error),
	TypeError,
	OtherCrateError(OtherCrate::Error),
	NegativeInt,
	IntTooLarge,
	IntTooSmall,
	FloatInf,	
}
```

Now with all of these extra error types we get to enjoy writing first our `fmt` block:
```rust
impl std::fmt::Display for LaissezError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotEven => write!(f, "the number is not even"),
            Self::ParseInt(error) => write!(f, "failed to parse integer: {error}"),
            Self::Zero => write!(f, "the number cannot be zero"),
            Self::IO(error) => write!(f, "I/O error: {error}"),
            Self::TypeError => write!(f, "the value had the wrong type"),
            Self::OtherCrateError(error) => write!(f, "other crate error: {error}"),
            Self::NegativeInt => write!(f, "the number cannot be negative"),
            Self::IntTooLarge => write!(f, "the number is too large"),
            Self::IntTooSmall => write!(f, "the number is too small"),
            Self::FloatInf => write!(f, "the floating-point value was infinite"),
        }
    }
}
```

Well that wasn't too bad. You can use match auto fill if your IDE supports it then just complete each branch. Still a bit tedious. But now there are still the `From` blocks for the errors being wrapped in our error:
```rust
impl From<std::num::ParseIntError> for LaissezError {
    fn from(error: std::num::ParseIntError) -> Self {
        Self::ParseInt(error)
    }
}

impl From<std::io::Error> for LaissezError {
    fn from(error: std::io::Error) -> Self {
        Self::IO(error)
    }
}

impl From<OtherCrate::Error> for LaissezError {
    fn from(error: OtherCrate::Error) -> Self {
        Self::OtherCrateError(error)
    }
}
```

Not too bad right? But now imagine writing all of those error variants at the beginning, before writing even the `divide_by_two()` function, and then later finding that many of the errors were not necessary or even made sense as the crate grows and changes. Instead, why not just write the errors as they arise? Hence: *Laissez-Faire Errors*. Just write them as they become necessary. The smallest iteration I can think of is still, a single `enum` branch with the `fmt`. Once you have that, it's very trivial to add another variant. Anyhow, it can be even simpler to write errors as well....

### cargo add [anyhow](https://docs.rs/anyhow) / [thiserror](https://docs.rs/thiserror/latest/thiserror/)
If you are looking to simplify your errors a step further, you can try the *thiserror* crate. if we wanted to apply it to our error type we could do something like:
```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum LaissezError {
	#[error("The number is not even!")]  
	NotEven,
	#[error("failed to parse value, {0}")]
	ParseInt(#[from] std::num::ParseIntError),
}
```

This works well, but if you aren't working with a particular need for a diverse set of errors, we can simplify it further with the *anyhow* crate, and handle the errors in the actual functions returning `Result`:
```rust
use anyhow::{bail, Context, Result};

pub fn divisible_by_two(input: i32) -> Result<i32> {
    match input % 2 {
        0 => Ok(input),
        _ => bail!("the number is not even!"),
    }
}

pub fn parse_and_check(input: &str) -> Result<i32> {
    let number = input
        .parse::<i32>()
        .with_context(|| format!("failed to parse value, {input}"))?;

    divisible_by_two(number)
}
```

Both approaches simplify error handling, and both fit the philosophy of *Laissez-Faire* errors: add structure only when the code actually needs it. Personally I am a fan of implementing my errors manually, as I find writing errors in Rust to be easy and intuitive, and using a third-party crate overkill, unless there's a specific need to simplify error handling further. 

## Laissez-Faire Errors --end
Hopefully this post has shown that writing errors in Rust is best done as the need arises, and that error handling should never impede a project. Moreover, idiomatic error handling makes the matter of managing when to use an `Err` variant clearer and less prone to confusion. The goal of a good error is to tell you what went wrong. In a user-facing application, that could be a pop-up message: "Failed to upload file", and with a server application it would likely be appending the error to a log file, with a timestamp - NOT `unwrap()`, if you expect the application to recover from errors. 
