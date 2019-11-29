# Hiss

Hiss is a toy implementation of [Shamir's Secret Sharing](https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing)

*DO NOT* use it for anything critical: it's based on a cryptographically secure algorithm, but my implementation may have inadvertently introduced a weakness.

However, feel free to have fun with it!

![Generating keys from a file](https://raw.githubusercontent.com/Tak/hiss/master/images/generate.png)
![Reconstructing a file](https://raw.githubusercontent.com/Tak/hiss/master/images/reconstruct.png)

## Installation

- Clone this repository
- [Install ruby](https://www.ruby-lang.org/en/downloads)
- Install bundler: Open a terminal and run the command `gem install bundler`
- Run `bundle install` from the `hiss` directory

## Usage

- Run `bundle exec exe/hiss`

