#![no_main]

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
    Target::UrlParse(url, base) => {
      let _ = deno_url::op_url_parse::call(url, base);
    }
    Target::UrlReparse(url, opts) => {
      let _ = deno_url::op_url_reparse::call(url, opts);
    }
    Target::UrlParseSearchParams(args, buf) => {
      let zc = buf.map(serde_v8::ZeroCopyBuf::new_temp);
      let _ = deno_url::op_url_parse_search_params::call(args, zc);
    }
    Target::UrlStringifySearchParams(args) => {
      let _ = deno_url::op_url_stringify_search_params::call(args);
    }
  };
});
