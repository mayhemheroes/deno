#![no_main]

use deno_core::url;
use libfuzzer_sys::fuzz_target;

#[derive(Debug, arbitrary::Arbitrary)]
enum Target {
  UrlParse(String, Option<String>),
  UrlReparse(String, (u8, String)),
  UrlParseSearchParams(Option<String>, Option<Vec<u8>>),
  UrlStringifySearchParams(Vec<(String, String)>),
}

fuzz_target!(|target: Target| {
  match target {
    Target::UrlParse(href, base) => {
      let base_url = base.as_deref().and_then(|b| url::Url::parse(b).ok());
      let opts = url::Url::options();
      let _ = match base_url.as_ref() {
        Some(b) => opts.base_url(Some(b)).parse(&href),
        None => url::Url::parse(&href),
      };
    }
    Target::UrlReparse(href, (setter_idx, value)) => {
      if let Ok(mut parsed) = url::Url::parse(&href) {
        match setter_idx % 9 {
          0 => { url::quirks::set_hash(&mut parsed, &value); }
          1 => { let _ = url::quirks::set_host(&mut parsed, &value); }
          2 => { let _ = url::quirks::set_hostname(&mut parsed, &value); }
          3 => { let _ = url::quirks::set_password(&mut parsed, &value); }
          4 => { url::quirks::set_pathname(&mut parsed, &value); }
          5 => { let _ = url::quirks::set_port(&mut parsed, &value); }
          6 => { let _ = url::quirks::set_protocol(&mut parsed, &value); }
          7 => { url::quirks::set_search(&mut parsed, &value); }
          _ => { let _ = url::quirks::set_username(&mut parsed, &value); }
        }
      }
    }
    Target::UrlParseSearchParams(args, buf) => {
      let input: Vec<u8> = match (args, buf) {
        (Some(s), _) => s.into_bytes(),
        (None, Some(b)) => b,
        (None, None) => return,
      };
      let _ = url::form_urlencoded::parse(&input)
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect::<Vec<_>>();
    }
    Target::UrlStringifySearchParams(args) => {
      let _ = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(args)
        .finish();
    }
  };
});
