+++
title = "Gloo + Yew for persistent webapp state"
date = 2026-09-09

[taxonomies]
tags = ["rust", "yew", "webassembly", "gloo", "web-development"]
+++

I have been tinkering with a side project for a while where the goals are pretty simple:
1) the application's state needs to be preserved between sessions
2) it needs to be client side only
3) Rust
I originally went with [Leptos](https://leptos.dev/) for building the web app that I wanted, and while I was getting along with working with Leptos' props and contexts, I slowly realized I didn't want to pass props around between views. As the complexity of the application grew it was getting to be more of a headache to pass around the data I wanted to work with. But I continued developing and tinkering.
<!-- more -->

Eventually I came to the conclusion that I would need to use the [Web Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API) for either `sessionStorage` or `localStorage`. Likely `localStorage`. Why? Because I was building something where the user could update / interact with some of the application and it would be preferable if those changes were available between uses, on the same browser. This is a small hobby project and I have had no interest in setting up any server side storage at all, so doing everything client side and using the correct web storage api made sense to me.

Looking around, at the documentation, it was abundantly clear that `localStorage` was exactly what I wanted:
> `localStorage` is partitioned by [origin](https://developer.mozilla.org/en-US/docs/Glossary/Origin) only. All documents with the same origin have access to the same `localStorage` area, and it persists even when the browser is closed and reopened.

Awesome! So now I just needed to implement the logic in Leptos and get going. But here I ran into a problem, Leptos' documentation makes reference to using `localStorage` but I wasn't really understanding the explanation of use and kept getting lost looking for an example of what I was looking for. Eventually I stumbled across [gloo](https://gloo-rs.web.app/), and specifically their `storage` crate.
## [gloo_storage](https://crates.io/crates/gloo-storage) --doc
Looking at the [docs](https://docs.rs/gloo-storage/latest/gloo_storage/) for gloo_storage I was quickly underwhelmed again as it only lists a single sentence introduction, no examples, and just the structs and traits available. Ok then. But reading the description I realized I was making things more complicated than they needed to be:

> This crate provides wrappers for the [Web Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API)

So all I needed to do was consult the web storage api and go from there! Great! 

Next problem... I was done with Leptos.
## --remove leptos --add yew
It had been a while since I checked out [yew](https://yew.rs/) and after looking around to see if I could avoid complexity via props, I came across this great [concepts page](https://yew.rs/docs/next/concepts/contexts) on the yew website. Not only did their example of the problem exactly sum up my naive implementation where I wound up prop drilling again and again, but the tool that yew now supports called *Context* seemed exactly like what I wanted to do (I should note I don't know what Leptos has that could be comparable or better than yew's context but I made the switch all the same). 

So now I had my tech stack, maybe? gloo_storage for my persistence, and yew for my web application architecture. Awesome. Now I needed to test things out. 
## cargo run -- --example
Now that i have given the back story to how I came to wanting to try yew + gloo, lets make a simple example that illustrates what I want from the persistent storage. Lets start by defining how the example should operate:
take user input -> store input persistently -> update application state 

Seems pretty straight forward. First we should make sure we have trunk installed:
```bash
cargo install trunk
```

Then we can make our new project:
```bash
cargo new gloo-yew
cd gloo-yew
```
then we should get our imports:
```bash
cargo add yew --features csr
cargo add gloo-storage
cargo add serde
```
What are the features we chose? `csr` is for *client side rendering*, remember we want everything to happen on the client side, so nothing will be rendered from the server. We will need to use the [Serde](https://crates.io/crates/serde) crate for serialization. But why do we need serde for this project if we aren't going to need to send anything to the server?
### Serde - the powerhouse of the cell
While you may have primarily seen serde being used to serialize and deserialize data for doing something like sending it to/from a server as json, its still very handy elsewhere where you want to serialize / serialize your Rust structs. And guess how we are going to store our application's state? Structs! 

What we'll plan to do is convert our data structure to json then use the `localStorage` api to store the json locally, then we can read from the storage to update our application during use. 

We'll need a struct. So lets just decide what the example should hold, I think a text box that the user can input their name, the current name output next to the text box, should be sufficient to test that gloo + yew are working correctly!
```rust
struct UserInfo {
	name: String
}
```
We  can call it `UserInfo` since we might want to extend it later on to add more user information and test the storage/update pipeline is working properly. 

We should probably add `serde` too:
```rust
#[derive(Serialize, Deserialize, Clone, Default, PartialEq)]
struct UserInfo
```

I am adding `Clone`, `PartialEq`, and `Default` as well because we will need these derives to work with our state. We are going to have to clone, and start with the default value for our field, which should just be `String::new()`, for an initial state before receiving any user input.

One more thing before we build this, lets add support for `web-sys` so we can work with the html `input` tag and get our user input!
```bash
cargo add web-sys
```

[web-sys](https://crates.io/crates/web-sys) is a binding for Web APIs, and yew [recommends it](https://yew.rs/docs/next/concepts/basic-web-technologies/web-sys). 

Now let's get our application skeleton done!

### trunk serve --open example

We'll keep the application as simple as possible and `main.rs` can just look something like this:
```rust
use gloo_storage::{LocalStorage, Storage};
use serde::{Deserialize, Serialize};
use web_sys::HtmlInputElement;
use yew::prelude::*;

const STORAGE_KEY: &str = "user-info";

type UserInfoContext = UseStateHandle<UserInfo>;

#[derive(Serialize, Deserialize, Clone, Default, PartialEq)]
struct UserInfo {
    name: String,
}

#[component]
fn App() -> Html {
    let state = use_state_eq(|| {
        LocalStorage::get::<UserInfo>(STORAGE_KEY).unwrap_or_default()
    });

	use_effect_with((*state).clone(), move |user_info| {
		LocalStorage::set(STORAGE_KEY, user_info)
			.expect("failed to save state");
	});

    html! {
        <ContextProvider<UserInfoContext> context={state}>
            <Name />
        </ContextProvider<UserInfoContext>>
    }
}

#[component]
fn Name() -> Html {
    let state = use_context::<UserInfoContext>()
        .expect("no user info context found");

    let oninput = {
        let state = state.clone();

        Callback::from(move |event: InputEvent| {
            let input: HtmlInputElement = event.target_unchecked_into();

            let mut updated = (*state).clone();
            updated.name = input.value();

            state.set(updated);
        })
    };

    html! {
        <div>
            <input
                type="text"
                value={state.name.clone()}
                {oninput}
            />

            <p>{format!("Current name: {}", state.name)}</p>
        </div>
    }
}

fn main() {
    yew::Renderer::<App>::new().render();
}
```

So we have two `components`, one that takes the user input for the name, and outputs it right below, and another that runs our application. `App` will be our entry point the the Yew web app. 

One last thing we need, in the application root we will need our `index.html` file:
```html
<!doctype html> 
<html lang="en"> 
	<head> 
		<meta charset="utf-8" /> 
		<title>Yew + gloo_storage</title> 
	</head> 
	<body></body> 
</html>
```

Now we can run with `trunk serve --open`

Can you see where we are using those derives I mentioned earlier? We need to do a fair bit of cloning, and our `name` field needs a default value, in this case an empty string, because of how we access it via the `App`. But what about that `PartialEq`? I will admit when I was looking through the examples for working with gloo and yew, I didn't think it was necessary, but if we remove it we see:
```bash
error[E0277]: can't compare `UserInfo` with `UserInfo`
  --> src/main.rs:17:17
   |
17 |       let state = use_state_eq(|| {
   |  _________________^
18 | |         LocalStorage::get::<UserInfo>(STORAGE_KEY).unwrap_or_default()
19 | |     });
   | |______^ no implementation for `UserInfo == UserInfo`
   |
   = help: the trait `PartialEq` is not implemented for `UserInfo`
```

And there we see, it should have been obvious! Of course the method `use_state_eq` is going to need to be able to check equality in some way. So what is the `use_state_eq()` doing here? This is probably the messiest bit to look at and might seem intimidating at first. 

Notice that we need to use a closure with no argument first why? If we look at the [documentation](https://docs.rs/yew/latest/yew/functional/fn.use_state_eq.html) for `use_state_eq` we can see that the parameter type it accepts is `init_fn: F`. So from the documentation `F` much implement `FnOnce()`. What the heck is that? Lets look at the [trait](https://doc.rust-lang.org/std/ops/trait.FnOnce.html) documentation:
> Instances of `FnOnce` can be called, but might not be callable multiple times. Because of this, if the only thing known about a type is that it implements `FnOnce`, it can only be called once.

Ok so basically we need to pass something to `use_state_eq` to initialize our `state` variable and use it in our function. Why the `eq` part? This is because, as per the definition for `use_state`:
> This hook will always trigger a re-render upon receiving a new state. See [`use_state_eq`](https://docs.rs/yew/latest/yew/functional/fn.use_state_eq.html "fn yew::functional::use_state_eq") if you want the component to only re-render when the new state compares unequal to the existing one.

Ok, so we use the `use_state_eq` to only trigger a re-render when we update the user name. So whats going on inside of the closure? 
#### LocalStorage for well local storage
`LocalStorage::get::<UserInfo>(STORAGE_KEY).unwrap_or_default()` allows us to access the value we are using to store our app state. The first time we run the app there will be no stored state, so instead of crashing our application we just default back to `UserInfo::default()`, which gives us our empty `String`. Once things have been initialized, Yew maintains the state for us between re-renders and won't need to read from the local storage for each re-render.

So then what are we doing here? 
```rust
	use_effect_with((*state).clone(), move |user_info| {
		LocalStorage::set(STORAGE_KEY, user_info)
			.expect("failed to save state");
	});
```

We apply `use_effect_with` in order to hook the lifecycle and create a side effect, in this case, updating our local storage. Why do we need `(*state).clone()` though? Here we need to step out of our handle: `UseStateHnadle<UserInfo>` and directly gain access to our `UserInfo`, then we need an owned copy of the `UserInfo`. Then if the value changes we call the `set` function for the local storage, and set it to our current `user_info` value!  

Here is also where we get to use serde, technically for the second time, as we also use it to convert our stored state into our `UserInfo` struct. We can verify that this is happening if we view the local storage file (inspect element -> Storage -> Local Storage in firefox):
```json
user-info:"{"name":"Alex"}"
```

awesome! We see our key is `user-info` which is what we expected it to be, then our struct's single field with the name as the value! 

There we have it, a working example of how to take user input and store it through the browser, all totally local, and have it persist across sessions! As long as the local storage isn't cleared we will have our data!
