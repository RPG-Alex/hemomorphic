+++
title = "post.explain_builders().build()"
date = 2026-02-01T19:00:50+08:00

[taxonomies]
tags = ["rust", "blogging","builder-pattern","idiomatic","build-patterns"]
+++

# struct Builder
In my last [post](@/posts/sql-docs.md) I started to explore using the [`builder` pattern](https://en.wikipedia.org/wiki/Builder_pattern) in Rust. In this post I want to go a bit more in depth about what a `builder` is and why it can be a versatile, *idiomatic* tool. They are especially helpful in situations where you might otherwise reach for patterns you are used to coming from another language and be wondering how to do the same in Rust without falling into an anti-pattern or battling the [borrow checker](https://doc.rust-lang.org/1.8.0/book/references-and-borrowing.html).

 Builders are a handy and *idiomatic* pattern to use when:
- You want to use something like [overloading](https://en.wikipedia.org/wiki/Function_overloading) (if you are coming from an Object Oriented Language)
- would like to have `default` values that can be overwritten when needed at creation
- Have a large number of possible inputs
- Want optional add-ons
- or anywhere you don't want a `new(..)` method that looks like a grocery list.  
<!-- more -->

## impl Builder --introduction
Before creating [sql-docs](https://crates.io/crates/sql_docs) I was not very familiar with the build pattern, though I had been using it without really realizing what I was using for a while. It is very intuitive to use, as you chain together your `builder` methods. I'll include a simple example of where a `builder` could be helpful and *build* on it as we go (pun intended):
```rust
pub struct Order {
    dish: String
}

impl Order {
    pub fn new(dish: String) -> Self {
        Self {
            dish
        }
    }
}
```

# impl Order --first-iteration
For the example scenario of this post, imagine we are making a backend for a point of sale machine that a restaurant can use to track table orders. 

Right now it's not the most descriptive structure but it is able to store orders. Maybe the struct `Order` can be modified to represent an order, which could have multiple dishes, drinks, and a few other things:

```rust
pub struct Order {
    appetizer: String,
    main_course: String,
    drink: String,
    dessert: String,
    price: f64,
}
impl Order {
    pub fn new(
    appetizer: String,
    main_course: String,
    drink: String,
    dessert: String,
    price: f64,
    ) -> Self {
        Self {
            appetizer
            main_course
            drink
            dessert
            price
        }
    }
}
```

This is starting to get pretty big and there are still a lot of things an order could include, lets make a more exhaustive list and see just how unwieldy a naive approach to creating a `new()` order could be: 
```rust
pub struct Order {
    appetizer: String,
    appetizer_notes: String,
    main_course: String,
    main_course_notes: String,
    side_dish: String,
    side_dish_notes: String,
    drink: String,
    drink_size_ml: u64,
    drink_notes: String,
    dessert: String,
    dessert_notes: String,
    table_number: u64,
    guest_count: u64,
    is_takeout: bool,
    total_price: f64,
    special_instructions: String,
}

impl Order {
    pub fn new(
        appetizer: String,
        appetizer_notes: String,
        main_course: String,
        main_course_notes: String,
        side_dish: String,
        side_dish_notes: String,
        drink: String,
        drink_size_ml: u64,
        drink_notes: String,
        dessert: String,
        dessert_notes: String,
        table_number: u64,
        guest_count: u64,
        is_takeout: bool,
        total_price: f64,
        special_instructions: String,
    ) -> Self {
        Self {
            appetizer,
            appetizer_notes,
            main_course,
            main_course_notes,
            side_dish,
            side_dish_notes,
            drink,
            drink_size_ml,
            drink_notes,
            dessert,
            dessert_notes,
            table_number,
            guest_count,
            is_takeout,
            total_price,
            special_instructions,
        }
    }
}
```

Stay with me, I realize there are other optimizations we can do besides implementing a `builder` but I wanted to illustrate a point. If you aren't familiar, [clippy](https://doc.rust-lang.org/stable/clippy/) has a lot of customization options and can make your code more or less idiomatic down to the minimum it will allow without modifying the `Cargo.toml`'s linting settings and simply running: `cargo check`. If we run: 
```bash
cargo clippy -- -D clippy::too_many_arguments
```
We can get a warning about this:
```text
error: this function has too many arguments (16/7)
  --> src/main.rs:44:5
   |
44 | /     pub fn new(
45 | |         appetizer: String,
46 | |         appetizer_notes: String,
47 | |         main_course: String,
...  |
60 | |         special_instructions: String,
61 | |     ) -> Self {
   | |_____________^
   |
   = help: for further information visit https://rust-lang.github.io/rust-clippy/master/index.html#too_many_arguments
   = note: requested on the command line with `-D clippy::too-many-arguments`
```
So the default level appears to be 7 arguments max and we have 16! But obviously we have a mess of fields that seem like they could all be abstracted a bit more feasibly. Lets refactor our struct `Order` one more time before implementing a `builder`: 
```rust
pub struct Item {
    name: MenuItem,
    price: i64, // convert prices to smallest denomination to avoid float messes
    notes: Option<String>,
}

pub struct Order {
    items: Vec<Item>,
    table: Option<u8>,
    table_instructions: Option<String>,
}
```

That is much clearer and helps conceptualize how an order works. I am omitting anything for the `MenuItem` just imagine it holds the value for the menu item (name, ingredients, etc). I'm leaving price on `Item` because we're placing an order and using an i64 to avoid decimals (€130.30 becomes `13030`). We can abstract away a lot by simply using an `Option<>`, such as now making table and order item notes optional, as well as making take-out implicit to the `table: Option<u8>` field (no table for take away!). Now we can start to discuss what functionality we might want to implement with our `builder` pattern!

# impl Builder --plan
Now that we have a nice clean abstraction to work with, lets think about the process a server might go through to put an order into the system:

1. Select item from menu list, lets say *Steak*
2. Open the individual item view
3. In the item view the server is prompted to:
    - select price (maybe a 10% because steak is on special)
    - add a note to order: "Medium-rare, light butter"
3. Return to the menu list, to select a drink: *Bourbon*
4. In the bourbon view set the notes to "on ice"
5. Enter the order into the system for the kitchen to see (build the order)

This is probably a bit simple and I would rather have a separate way to represent how to cook a steak/dish with multiple cooking choices, but for the purposes of this post this should suffice!

## impl Builder --step-1
So then how do we add this functionality? We could do something like:
```rust
impl Order {
    new(items: Vec<Item>, table: Option<u8>, instructions: Option<String>) -> Self {
        Self {
            items,
            table,
            instructions,
        }
    }
}

let order = Order::new(
    vec![
        Item {
            name: MenuItem::Steak,
            item_type: ItemType::Entree,
            price: 270, 
            notes: Some("medium rare, light butter".to_string()),
        },
        Item {
            name: MenuItem::Bourbon,
            item_type: ItemType::Drink,
            price: 120,
            notes: Some("on ice".to_string()),
        },
    ],
    Some(12), 
    None,     
);

```

But it would become increasingly messy to write this out as our system gets fleshed out and functionality gets added in. We can take advantage of a `builder` to fill out the order piece by piece. Let's start by introducing a new `builder` structure:
```rust
#[derive(Debug)]
pub struct OrderBuilder {
    order: Order
}
```
For this example, the `builder` simply wraps `Order` directly. In a real system you might use a separate internal representation, but this keeps the example focused on the pattern.

**That's it? That's our builder?**

A `builder` can be pretty much any shape you need to get the job done. In our case we don't need anything too fancy. We are basically going to wrap our `Order` struct in our `builder` and go from there. 

## impl Builder --step-2 update-order
Our next order of business is to update the `Order` so that when you call an order it returns our `OrderBuilder`:

```rust
impl Order {
    pub fn builder() -> OrderBuilder {
        OrderBuilder::new()
    }
}
```
We can keep this nice and simple for the example but imagine you started adding lots of new methods on `Order` that were intended to work on a completed and immutable `Order` and not used to update values as a `builder` does. Then the separation of concerns really starts to make sense, as we'll see. Exposing `builder()` on `Order` makes discovery trivial and keeps construction colocated with the type it produces.

## impl Builder --step-3 defaults
You may have noticed above calling the `builder` is done through the use of a `new()` method that takes 0 parameters. We are doing that to give us a skeleton of an empty `OrderBuilder`, and then we can update the skeleton as needed. We can start this process by adding an implementation for `Default`, so we have our skeleton:
```rust
impl Default for OrderBuilder {
    fn default() -> Self {
        Self {
            order: Order {
                items: Vec::new(),
                table: None,
                table_instructions: None,
            },
        }
    }
}

impl OrderBuilder {
    pub fn new() -> Self {
        Self::default()
    }
}
```
Nothing too exciting but we can now easily get a default `builder` for use later. 
## impl Builder --step-4 chained methods
Chaining methods in the `builder` is really where its utility becomes apparent. This pattern allows us to have an immutable final `Order` while adding in whatever we want to that structure beforehand, and with idiomatic method naming it should be very clear what we are doing as we do it. 

Let's start with a finished `Order` creation statement and then breakdown the methods we will need to accomplish it:
```rust
let item_1 = Item::new(Steak, 300, Some("Medium rare, light butter".to_owned()));
let item_2 = Item::new(Bourbon, 150, Some("on ice".to_owned()));
let new_order = Order::builder()
    .table(13)
    .add_item(item_1)
    .add_item(item_2)
    .table_instructions("Bring bourbon before Steak")
    .build();
```
Here we can see that we first create our items, then to build our order, we chain as many methods as we need to in order to fill out our skeleton of an `Order`. We can do the same thing without chaining if we make `new_order` mutable:
```rust
let mut new_order = Order::builder()
    .table(13);
new_order
    .add_item(item_1)
    .add_item(item_2);
new_order.table_instructions("Bring bourbon before Steak")
order = new_order.build();
```
 No matter what we end our build with the `build()` method! Nice and clean. Notice we did a reassignment this time after making `new_order` mutable, this is to retain ownership of the built `Order` and regain immutability. 

 To accomplish the above here is our finished `OrderBuilder`:
```rust
impl OrderBuilder {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn table(mut self, table: u8) -> Self {
        self.order.table = Some(table);
        self
    }

    pub fn table_instructions<S: Into<String>>(mut self, instructions: S) -> Self {
        self.order.table_instructions = Some(instructions.into());
        self
    }

    pub fn add_item(mut self, item: Item) -> Self {
        self.order.items.push(item);
        self
    }

    pub fn build(self) -> Order {
        self.order
    }
}
```

# struct Conclusion
This was a fun and simplified example I thought of to illustrate a design pattern that I have found to be very helpful when using Rust. I took inspiration from the [Rust Design Patterns](https://rust-unofficial.github.io/patterns/patterns/creational/builder.html) section on Builders, along with a possibly outdated Rust [style guide](https://doc.rust-lang.org/1.12.0/style/ownership/builders.html). In both cases I thought the `builder` pattern was a little under built (again pun intended, no apologies!) and wanted to give my own spin on a simple example to illustrate the concept. I hope you found it informative or even helpful. If this were a `builder` I would want to use in the real world I would probably make the structure for the `OrderBuilder` a bit more unique, rather than simply wrapping an `Order`, but for this post I think it serves the illustrative goal of how to use a `builder`. Builders allow for separating concerns between creating an object and using an object, allowing for a cleaner separation between those two steps. We could have just as easily put everything into the `Order` struct and just avoided any naming clashes such as renaming `table` to `set_table` and so on. But doing things this way helps communicate our intent for future us and others that may one day find themselves using our code. 