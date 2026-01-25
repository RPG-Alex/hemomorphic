+++
title = "// sql-docs: published on crates.io!"
date = 2026-01-25T19:47:08+08:00

[taxonomies]
tags = ["rust", "blogging","sql","parsing","project"]
+++

# cargo publish [`sql-docs`](https://crates.io/crates/sql_docs)

I am happy to announce that I have completed my first crate and published it to *[crates.io](https://crates.io)*!
<!-- more -->
## experience --sql-docs creation

This crate has a pretty specific use case for extracting comments from `sql` files. I learned quite a bit about [parsers](https://en.wikipedia.org/wiki/Parsing), as well as creating more idiomatic Rust. I started the project with an idea of the externally facing APIs I wanted to write. However I wound up making several revisions that led to much cleaner APIs and drove me into using a [`builder` pattern](https://doc.rust-lang.org/1.0.0/style/ownership/builders.html). Moreover, I finally had an excuse to work with [lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html) and while only for one struct, and technically only for one field in that struct, I did have a good reason to do so. 

I also gained a lot of experience writing my own tests and then creatively adding test helper functions. Overall I learned to write tests that I think are clear and genuinely test expected functionality. 

Finally, my crate has been integrated into another repo called [sql-traits](https://github.com/earth-metabolome-initiative/sql-traits), and the real time feedback I received to make sure `sql-docs` was up to snuff performance wise was the cherry on top for this experience. 

## // project-goal

The goal for this project was to take an SQL file such as: 

```sql
-- Table that houses user data 
CREATE TABLE users (
    -- primary key for table 
    id          INT PRIMARY KEY,
    -- field for storing usernames. max of 50 characters
    username    VARCHAR(50) NOT NULL,
    ...
);
```
This is a pretty generic example but it shows the kinds of comments I would like to extract from the SQL data. The goal would be to extract the comments, and structure them like this: 
```rust
TableDoc {
    schema: None,
    name: "users",
    doc: Some("Table that houses user data"),
    columns: vec![
        ColumnDoc {
            name: "id",
            doc: Some("primary key for table")
        },
        ColumnDoc {
            name: "username",
            doc: Some("field for storing usernames. max of 50 characters")
        }
    ],
    path: Some("mysqlfile.sql")
}
```
This structure is handy as it groups the comments by table and column, and accounts for a potential `schema` that may be present. One of the first things you'll notice is the metadata on the table. the `path` field wound up being important later on for an API endpoint I needed to add for parsing from `String`s.

### //intended-use

The top level API that is the entry point for the crate is a structure called `SqlDoc`:
```rust
/// Top-level documentation object containing all discovered [`TableDoc`] entries.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SqlDoc {
    /// Holds the [`Vec`] of all tables found in all specified files.
    tables: Vec<TableDoc>,
}
```
`SqlDoc` itself is just a wrapper struct around the `Vec<TableDoc>` but with integration with a builder struct and some handy methods like:
```rust
 pub fn table(&self, name: &str, schema: Option<&str>) -> Result<&TableDoc, DocError>
 ```
 Which lets you find a single `TableDoc` and runs in `O(log n)` thanks to using binary search to find the table and possibly duplicates that may exist (which would be bad). 

## /// Example of [`SqlDoc`] intended use

The crate's API implements a builder and can look like this: 
```rust
use sql_docs::SqlDoc;

let generated_docs = SqlDoc::from_dir("the_dir").deny("deny.sql").build();
```

In the above code snippet, a `dir` is specified. There are three primary constructors: 

1) `from_dir("Path")`: The most robust entry route for the crate. This will create an `SqlDocBuilder` struct and populate the `source` field of the builder, and then the chained `deny("deny.sql")` will populate the `deny` field, which is a vector of `Strings` that are used at build time to filter out any undesired SQL files (note that non SQL files are automatically filtered). 

2) `from_path("Path")`: This method expects the specific path for a single `sql` file and will also return an `SqlDocBuilder` instance, though the `deny()` doesn't apply. 

3) `from_str("str")`: If the `sql` statements and comments in question already reside in a `str` somewhere, this method allows the comments to be parsed without the need for a file. This method was created for the purpose of fuzzing and is utilized in the fuzz harness I wrote. 

Regardless of method chosen, all will return a `SqlDocBuilder` and then to complete the operation the method `build()` is invoked, to actually build the `SqlDoc`! This all sounds very reasonable but this was the first time I had tried implementing a builder and indeed the first time encountering a builder. I am now a big fan of builders and find myself wondering "do I need a builder for this?" more and more when working on new stuff.

```rust
enum SqlFileDocSource<'a> {
    Dir(PathBuf),
    File(PathBuf),
    FromString(&'a str),
}
```
The source is stored in an enum, which helps streamline the `build` process. 

Notice that this is where I got to use an explicit lifetime, as the `FromString` enum variant contains a `str` which requires specifying the lifetime! Why do this? A `String` would probably be fine but given the `FromString` is mostly intended to be used for parsing, it would be nice to avoid using the heap and adding any overhead, as this crate was intended to at least try to be performant! 

## cargo sql-docs --docs

For this project I used very strict linting rules to ensure I wasn't getting lazy and help me avoid accidentally running into any *antipatterns*:
```toml
[lints.rust]
missing_docs = "forbid"
unreachable_patterns = "forbid"
unused_must_use = "forbid"
unused_import_braces = "forbid"
unconditional_recursion = "forbid"
unused_macro_rules = "forbid"
deprecated = "deny"
unsafe_code = "forbid"

[lints.clippy]
unreadable_literal = "allow"
missing_panics_doc = "allow"
struct_excessive_bools = "allow"
should_panic_without_expect = "allow"
clone_on_copy = "forbid"
unwrap_used = "deny"
expect_used = "deny"
pedantic = { level = "deny", priority = -1 }
cargo = { level = "deny", priority = -1 }
nursery = { level = "deny", priority = -1 }
multiple_crate_versions = "allow"
```

While this may seem a bit masochistic, I think in light of recent Rust events, like [CloudFlare's use of `unwrap()` in production](https://news.ycombinator.com/item?id=45974052), not permitting myself to make the same type of mistakes seemed like a no brainer for ensuring my crate was safe for other people to rely on. 

Of specific note was the `missing_docs = "forbid"` which at first I despised as I felt it slowed me down, but having it turned on forced me to write my documentation after I had added a new `Struct` or a new method or even a new field to a `Struct`.

As a result, when I actually ran `cargo doc` my documentation was clear and with the heavier linting happening, my `README.md` examples were also tested and I could be confident I really was shipping something that would work out of the box and as advertised. 

### parse --help

The main challenge with this project was creating a parser that would account for a few invariants: 

1) Comments are only parsed if they immediately precede a statement

2) Single Line `--` comments and Multiline `/* */` comments are both valid 

3) SQL Statements themselves need to be valid before parsing their comments 

With these concepts in mind I got to work. `3` was the easiest for me to implement thanks to the [datafusion-sqlparser-rs](https://github.com/apache/datafusion-sqlparser-rs) crate; which I used to parse the SQL Statements. If the `sql` was parsed successfully then I would take the [AST](https://en.wikipedia.org/wiki/Abstract_syntax_tree) of statements and compare that against an AST of comments that is generated alongside the SQL Statements. And from there I'd generate my `SqlDocs`!

#### span.start() && span.end()

I looked into how DataFusion was parsing sql and noticed that they track the `span` of each statement, a span struct looking like this: 
```rust
pub struct Location {
    line: u64,
    column: u64,
}
pub struct Span {
    start: Location,
    end: Location,
}
```
This is my version of a `Span` that has a start and end `Location`. It basically mirrors the structure of the DataFusion parser's `Span` structure, and serves the same purpose. Great! Now once I have parsed a comment I can compare it with the starting span of each parsed statement and if the comment's start `Location` is one line above the statement, then add that comment to my AST! 

#### scan_comments(sql)

To accomplish parsing the sql comments I created a pretty hefty method called `scan_comments()` that would take the `sql` file data as an input and then collect all valid comments. 

```rust 
pub fn scan_comments(src: &str) -> CommentResult<Self> 
```

I got a little fancy with this and you'll notice I have a custom `Result` that looks like this:
```rust
/// Alias for comment results that may return a [`CommentError`]
pub type CommentResult<T> = Result<T, CommentError>;
```

The parsing in `scan_comments(..)` goes line by line, and specifically keeps track of whether or not it's already in a `multiline` comment or a `single line` comment, and if the parser is in a comment it collects the `char`s until it's no longer in a comment. Along the way I needed to add a few errors and tried to use my new `Span` and `Location` data to help make the errors more useful for the user. 

I utilized a `match` statement against 3 different values I used to track: `in_single`, `in_multi`, `c`. The first two are of course simply `bool` and track if you are in a comment or not. The `c` is the current `char` to be evaluated. Thus parsing simply becomes going line by line, looking for the characters marking a comment, and then once they are found, adding everything after them to the vector of comments. 

The parsing logic for ending a single line comment is pretty straightforward, anything on a line proceeding the `--` is taken as a comment, and once that line has ended, `in_single` is set back to `false`, marking the end of the comment. Then the comment is collected. 

It is similar for multiline comments but there are a couple caveats here as well: 

- Multiline comments must have an ending `*/` to mark their comment end. 

- Multiline comments are going to be on potentially... multiple lines! Thus when splitting line by line this needs to be accounted for. 

Once comments are parsed and collected for a file, they are then passed along to be compared against the parsed SQL Statements and if they are valid then they are finally returned! 

## cargo +nightly fuzz run sql_docs 

Fuzzing is quickly becoming one of my favorite things. For the uninitiated fuzzing is basically brute-force testing your code, and in my case, for any code state that could result in an unexpected `panic!` due to some bug in my code. Fuzzing is cool, it uses mutations, and [everyone is doing it](https://en.wikipedia.org/wiki/Fuzzing)!

For this crate, I used [cargo fuzz](https://github.com/rust-fuzz/cargo-fuzz), which uses `libFuzzer`. I am quite new to writing a harness, which is the code the fuzzer will use as the entry point to your software, and at first I was using the default `&[u8]` for fuzzing, but after getting some feedback was able to understand that I could get away with using a `String` for fuzzing. My fuzzer looked like this:

```rust
#![no_main]

use libfuzzer_sys::fuzz_target;
use std::str;

use sql_docs::SqlDoc;

fuzz_target!(|data: String| {
    let _ = SqlDoc::from_str(&data)
        .deny("a.sql")
        .deny("b.sql")
        .build();

});
```

Though in the actual fuzzer I wrote in each variant on the builder that existed, each target item served the same purpose, to test as many possible inputs as possible and try to find somewhere I was still getting `panics!`. Luckily, after hours of running, Not a single crash was found! 

## // Performance Assumptions and Iterative Improvements

I was originally just adding each `Table` that I found to my `Vec<TableDoc>` inside of `SqlDoc`, but had it quickly pointed out to me that I was not sorting my tables and had made my `table()` method `O(n²)` in complexity for simply searching for a single table (of which there could hundreds or thousands of tables)! I realized I could add one single line at creation of the `SqlDoc` that would alleviate all downstream issues, within the `SqlDoc` `new()` method itself:
```rust
    pub fn new(mut tables: Vec<TableDoc>) -> Self {
        tables.sort_by(|a, b| a.name().cmp(b.name()));
        Self { tables }
    }
```
Just sort the Tabledocs by name now! Which meant that downstream binary searching could be confidently utilized and cut down in overhead by a LOT!

There were a few other spots where I made assumptions based on getting things working first, and then later needed to go back and make revisions but sorting tables (and later columns of tables too) was probably the biggest on performance. 

## // Conclusion

This project was an exciting excuse to dive into parsing, crate creation, documentation generation, and fuzzing, all topics I am interested in getting better with and using more! I am happy with the work I did. While this is a niche crate, having something up on crates.io that I wrote myself feels good. I have a few things in the pipeline for upcoming projects and can say my experience on this crate has given me the confidence and knowledge to work on these projects. Thanks for reading!