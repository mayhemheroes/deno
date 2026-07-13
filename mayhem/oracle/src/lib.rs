//! AUTHORED behavioral oracle for the `url-parse` harness code path.
//!
//! The harness fuzzes the `url` crate (historically reached via `deno_core::url`,
//! which is a straight re-export). Deno's own upstream test suite for this code
//! lives in `tests/unit/url_test.ts` and only runs against a fully-built `deno`
//! binary (V8 + the whole runtime, network-fetched fixtures) — it cannot be built
//! or executed inside the fuzz commit image, and it does not exercise the crate the
//! harness actually drives. So this is an AUTHORED known-answer suite over the exact
//! APIs the harness calls: `Url::parse`, base-relative parsing, the `quirks` setters,
//! and `form_urlencoded` parse/serialize. Every case asserts concrete output, so a
//! sabotage patch that neuters the code (e.g. `exit(0)` / no-op) fails it.

#[cfg(test)]
mod tests {
  use url::form_urlencoded;
  use url::quirks;
  use url::Url;

  #[test]
  fn parse_absolute() {
    let u = Url::parse("https://user:pass@example.com:8080/a/b?x=1#frag").unwrap();
    assert_eq!(u.scheme(), "https");
    assert_eq!(u.username(), "user");
    assert_eq!(u.password(), Some("pass"));
    assert_eq!(u.host_str(), Some("example.com"));
    assert_eq!(u.port(), Some(8080));
    assert_eq!(u.path(), "/a/b");
    assert_eq!(u.query(), Some("x=1"));
    assert_eq!(u.fragment(), Some("frag"));
  }

  #[test]
  fn parse_rejects_relative_without_base() {
    assert!(Url::parse("/just/a/path").is_err());
    assert!(Url::parse("not a url").is_err());
  }

  #[test]
  fn parse_with_base() {
    let base = Url::parse("https://example.com/dir/page.html").unwrap();
    let joined = base.join("../other.html").unwrap();
    assert_eq!(joined.as_str(), "https://example.com/other.html");
    let abs = base.join("//cdn.example.net/x.js").unwrap();
    assert_eq!(abs.as_str(), "https://cdn.example.net/x.js");
  }

  #[test]
  fn parse_normalizes_dot_segments_and_case() {
    let u = Url::parse("HTTP://EXAMPLE.COM/a/./b/../c").unwrap();
    assert_eq!(u.scheme(), "http");
    assert_eq!(u.host_str(), Some("example.com"));
    assert_eq!(u.path(), "/a/c");
  }

  #[test]
  fn quirks_setters_roundtrip() {
    let mut u = Url::parse("https://example.com/path").unwrap();
    quirks::set_hash(&mut u, "#frag");
    assert_eq!(u.fragment(), Some("frag"));

    quirks::set_search(&mut u, "?a=b&c=d");
    assert_eq!(u.query(), Some("a=b&c=d"));

    quirks::set_pathname(&mut u, "/new/path");
    assert_eq!(u.path(), "/new/path");

    quirks::set_hostname(&mut u, "other.example.org").unwrap();
    assert_eq!(u.host_str(), Some("other.example.org"));

    quirks::set_port(&mut u, "1234").unwrap();
    assert_eq!(u.port(), Some(1234));

    quirks::set_username(&mut u, "alice").unwrap();
    assert_eq!(u.username(), "alice");

    quirks::set_protocol(&mut u, "http").unwrap();
    assert_eq!(u.scheme(), "http");
  }

  #[test]
  fn form_urlencoded_parse() {
    let parsed: Vec<(String, String)> = form_urlencoded::parse(b"a=1&b=two&c=%20%26")
      .map(|(k, v)| (k.into_owned(), v.into_owned()))
      .collect();
    assert_eq!(
      parsed,
      vec![
        ("a".to_string(), "1".to_string()),
        ("b".to_string(), "two".to_string()),
        ("c".to_string(), " &".to_string()),
      ]
    );
  }

  #[test]
  fn form_urlencoded_plus_is_space() {
    let parsed: Vec<(String, String)> = form_urlencoded::parse(b"q=hello+world")
      .map(|(k, v)| (k.into_owned(), v.into_owned()))
      .collect();
    assert_eq!(parsed, vec![("q".to_string(), "hello world".to_string())]);
  }

  #[test]
  fn form_urlencoded_serialize() {
    let s = form_urlencoded::Serializer::new(String::new())
      .append_pair("name", "a b")
      .append_pair("sym", "x&y")
      .finish();
    assert_eq!(s, "name=a+b&sym=x%26y");
  }
}
