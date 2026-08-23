/// NLP Text Processing — Tokenization, n-grams, TF-IDF, and text utilities.
///
/// This package provides production-grade text processing primitives for
/// Natural Language Processing (NLP) tasks: word-level tokenization, n-gram
/// generation, TF-IDF vectorization, cosine similarity, and basic text
/// normalization.
///
/// ## Features
///
/// ### Tokenization
///
/// Splits text into tokens (words) by whitespace and punctuation, with
/// configurable lowercasing and stop-word filtering. Handles Unicode
/// characters by treating ASCII letters/digits as word characters and
/// everything else as delimiters.
///
/// ### N-grams
///
/// Generates n-grams (unigrams, bigrams, trigrams, etc.) from token sequences.
/// Supports both word-level and character-level n-grams.
///
/// ### TF-IDF Vectorization
///
/// Computes Term Frequency-Inverse Document Frequency vectors for a corpus
/// of documents. TF-IDF is a numerical statistic reflecting how important a
/// word is to a document in a collection. Uses the standard formula:
///
/// - TF(t, d) = count(t in d) / total_terms(d)
/// - IDF(t) = log(N / df(t))  (smoothed: log((1 + N) / (1 + df(t))) + 1)
/// - TF-IDF(t, d) = TF(t, d) * IDF(t)
///
/// ### Cosine Similarity
///
/// Computes cosine similarity between TF-IDF vectors for document comparison.
///
/// ## Complexity
///
/// | Operation              | Time          |
/// |------------------------|---------------|
/// | `tokenize`             | O(n)          |
/// | `ngrams`               | O(n)          |
/// | `tfidf_vectorize`      | O(D * T)      |
/// | `cosine_similarity`    | O(V)          |
///
/// where n = text length, D = #documents, T = avg terms/doc, V = vocab size.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Tokenization
// ---------------------------------------------------------------------------

///|
/// Tokenize text into words.
///
/// Splits on whitespace and punctuation. ASCII letters (a-z, A-Z) and digits
/// (0-9) form word characters; everything else is a delimiter. Consecutive
/// delimiters are treated as a single split.
///
/// If `lowercase` is true, all tokens are converted to lowercase.
pub fn tokenize(text : String, lowercase : Bool) -> Array[String] {
  let tokens : Array[String] = []
  let buf : Array[Char] = []
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if is_word_char(c) {
      if lowercase && c >= 65 && c <= 90 {
        // 'A'-'Z' -> 'a'-'z'
        buf.push((c + 32).unsafe_to_char())
      } else {
        buf.push(c.unsafe_to_char())
      }
    } else if buf.length() > 0 {
      tokens.push(String::from_array(buf))
      buf.clear()
    }
  }
  if buf.length() > 0 {
    tokens.push(String::from_array(buf))
  }
  tokens
}

///|
/// Tokenize with stop-word removal.
///
/// Stop words (common words like "the", "a", "is") are removed from the
/// output. The stop-word list is passed as a `Map[String, Unit]` for O(1)
/// lookup.
pub fn tokenize_with_stopwords(
  text : String,
  lowercase : Bool,
  stop_words : Map[String, Unit],
) -> Array[String] {
  let tokens = tokenize(text, lowercase)
  let result : Array[String] = []
  for i = 0; i < tokens.length(); i = i + 1 {
    if !stop_words.contains(tokens[i]) {
      result.push(tokens[i])
    }
  }
  result
}

///|
/// Check if a character code is a word character (letter or digit).
fn is_word_char(c : Int) -> Bool {
  (c >= 65 && c <= 90) || // A-Z
  (c >= 97 && c <= 122) || // a-z
  (c >= 48 && c <= 57) // 0-9
}

// ---------------------------------------------------------------------------
// N-grams
// ---------------------------------------------------------------------------

///|
/// Generate word-level n-grams from a token sequence.
///
/// For `n=1` returns unigrams (the tokens themselves). For `n=2` returns
/// bigrams (adjacent pairs), etc.
///
/// Returns an empty array if `tokens` has fewer than `n` elements.
pub fn ngrams(tokens : Array[String], n : Int) -> Array[String] {
  let result : Array[String] = []
  if n < 1 || tokens.length() < n {
    return result
  }
  for i = 0; i <= tokens.length() - n; i = i + 1 {
    let buf : Array[Char] = []
    for k = 0; k < n; k = k + 1 {
      if k > 0 {
        buf.push((32).unsafe_to_char()) // space
      }
      let tok = tokens[i + k]
      for c = 0; c < tok.length(); c = c + 1 {
        buf.push(tok[c].to_int().unsafe_to_char())
      }
    }
    result.push(String::from_array(buf))
  }
  result
}

///|
/// Generate character-level n-grams from a string.
///
/// For `n=3` returns all 3-character substrings.
pub fn char_ngrams(text : String, n : Int) -> Array[String] {
  let result : Array[String] = []
  if n < 1 || text.length() < n {
    return result
  }
  for i = 0; i <= text.length() - n; i = i + 1 {
    let buf : Array[Char] = []
    for k = 0; k < n; k = k + 1 {
      buf.push(text[i + k].to_int().unsafe_to_char())
    }
    result.push(String::from_array(buf))
  }
  result
}

// ---------------------------------------------------------------------------
// TF-IDF
// ---------------------------------------------------------------------------

///|
/// A TF-IDF vectorizer.
///
/// Call `fit` to build the vocabulary from a corpus, then `transform` to
/// convert documents into TF-IDF vectors. Or use `fit_transform` for both.
pub struct TfidfVectorizer {
  /// Vocabulary: term -> index in the vector.
  vocabulary : Map[String, Int]
  /// IDF values for each term in the vocabulary.
  idf : Array[Double]
  /// Number of documents in the training corpus.
  num_docs : Int
}

///|
/// Fit the vectorizer on a corpus of documents.
///
/// Builds the vocabulary and computes IDF values.
pub fn fit(documents : Array[Array[String]]) -> TfidfVectorizer {
  let num_docs = documents.length()
  let vocab : Map[String, Int] = Map([])
  let doc_freq : Map[String, Int] = Map([])
  // Count document frequencies
  for d = 0; d < num_docs; d = d + 1 {
    let doc = documents[d]
    let seen : Map[String, Unit] = Map([])
    for i = 0; i < doc.length(); i = i + 1 {
      let term = doc[i]
      if !seen.contains(term) {
        seen[term] = ()
        if doc_freq.contains(term) {
          doc_freq[term] = doc_freq[term] + 1
        } else {
          doc_freq[term] = 1
        }
      }
    }
  }
  // Build vocabulary (sorted for deterministic ordering)
  let terms : Array[String] = []
  for term in doc_freq.keys() {
    terms.push(term)
  }
  terms.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  let idf_arr = Array::make(terms.length(), 0.0)
  for i = 0; i < terms.length(); i = i + 1 {
    vocab[terms[i]] = i
    let df = doc_freq[terms[i]]
    // Smoothed IDF: log((1 + N) / (1 + df)) + 1
    idf_arr[i] = @math.ln((1.0 + num_docs.to_double()) / (1.0 + df.to_double())) +
      1.0
  }
  { vocabulary: vocab, idf: idf_arr, num_docs }
}

///|
/// Transform a document into a TF-IDF vector.
///
/// The document is an array of tokens. Returns a sparse-like dense array
/// where index i corresponds to vocabulary term i.
pub fn transform(
  vectorizer : TfidfVectorizer,
  document : Array[String],
) -> Array[Double] {
  let vocab_size = vectorizer.idf.length()
  let result = Array::make(vocab_size, 0.0)
  if document.length() == 0 {
    return result
  }
  // Count term frequencies
  let tf : Map[String, Int] = Map([])
  for i = 0; i < document.length(); i = i + 1 {
    let term = document[i]
    if tf.contains(term) {
      tf[term] = tf[term] + 1
    } else {
      tf[term] = 1
    }
  }
  // Compute TF-IDF
  let total = document.length().to_double()
  for term in tf.keys() {
    if vectorizer.vocabulary.contains(term) {
      let idx = vectorizer.vocabulary[term]
      let tf_val = tf[term].to_double() / total
      result[idx] = tf_val * vectorizer.idf[idx]
    }
  }
  // L2 normalize
  let mut norm = 0.0
  for i = 0; i < vocab_size; i = i + 1 {
    norm = norm + result[i] * result[i]
  }
  norm = norm.sqrt()
  if norm > 0.0 {
    for i = 0; i < vocab_size; i = i + 1 {
      result[i] = result[i] / norm
    }
  }
  result
}

///|
/// Fit and transform in one step. Returns the TF-IDF matrix (one vector per document).
pub fn fit_transform(
  documents : Array[Array[String]],
) -> (TfidfVectorizer, Array[Array[Double]]) {
  let vectorizer = fit(documents)
  let matrix : Array[Array[Double]] = []
  for d = 0; d < documents.length(); d = d + 1 {
    matrix.push(transform(vectorizer, documents[d]))
  }
  (vectorizer, matrix)
}

// ---------------------------------------------------------------------------
// Cosine Similarity
// ---------------------------------------------------------------------------

///|
/// Compute cosine similarity between two vectors.
///
/// Returns a value in [0, 1] for non-negative vectors (like TF-IDF), where
/// 1 means identical direction and 0 means orthogonal.
pub fn cosine_similarity(
  vec_a : Array[Double],
  vec_b : Array[Double],
) -> Double {
  let n = if vec_a.length() < vec_b.length() {
    vec_a.length()
  } else {
    vec_b.length()
  }
  let mut dot = 0.0
  let mut norm_a = 0.0
  let mut norm_b = 0.0
  for i = 0; i < n; i = i + 1 {
    dot = dot + vec_a[i] * vec_b[i]
    norm_a = norm_a + vec_a[i] * vec_a[i]
    norm_b = norm_b + vec_b[i] * vec_b[i]
  }
  let denom = norm_a.sqrt() * norm_b.sqrt()
  if denom == 0.0 {
    0.0
  } else {
    dot / denom
  }
}

// ---------------------------------------------------------------------------
// Text Normalization
// ---------------------------------------------------------------------------

///|
/// Convert a string to lowercase.
pub fn to_lowercase(text : String) -> String {
  let buf : Array[Char] = []
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c >= 65 && c <= 90 {
      buf.push((c + 32).unsafe_to_char())
    } else {
      buf.push(c.unsafe_to_char())
    }
  }
  String::from_array(buf)
}

///|
/// Remove leading/trailing whitespace from a string.
pub fn trim(text : String) -> String {
  let mut start = 0
  let mut end = text.length() - 1
  while start < text.length() && is_whitespace(text[start].to_int()) {
    start = start + 1
  }
  while end >= 0 && is_whitespace(text[end].to_int()) {
    end = end - 1
  }
  if start > end {
    return ""
  }
  let buf : Array[Char] = []
  for i = start; i <= end; i = i + 1 {
    buf.push(text[i].to_int().unsafe_to_char())
  }
  String::from_array(buf)
}

///|
/// Check if a character code is whitespace.
fn is_whitespace(c : Int) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "nlp: tokenize basic" {
  let tokens = tokenize("Hello World test", true)
  assert_true(tokens.length() == 3)
  assert_true(tokens[0] == "hello")
  assert_true(tokens[1] == "world")
  assert_true(tokens[2] == "test")
}

///|
test "nlp: tokenize with punctuation" {
  let tokens = tokenize("Hello, world! How are you?", true)
  assert_true(tokens.length() == 5)
  assert_true(tokens[0] == "hello")
  assert_true(tokens[1] == "world")
}

///|
test "nlp: tokenize case sensitive" {
  let tokens = tokenize("Hello World", false)
  assert_true(tokens.length() == 2)
  assert_true(tokens[0] == "Hello")
  assert_true(tokens[1] == "World")
}

///|
test "nlp: tokenize empty string" {
  let tokens = tokenize("", true)
  assert_true(tokens.length() == 0)
}

///|
test "nlp: ngrams bigrams" {
  let tokens = ["the", "quick", "brown", "fox"]
  let bigrams = ngrams(tokens, 2)
  assert_true(bigrams.length() == 3)
  assert_true(bigrams[0] == "the quick")
  assert_true(bigrams[1] == "quick brown")
  assert_true(bigrams[2] == "brown fox")
}

///|
test "nlp: ngrams unigrams" {
  let tokens = ["a", "b", "c"]
  let unigrams = ngrams(tokens, 1)
  assert_true(unigrams.length() == 3)
  assert_true(unigrams[0] == "a")
}

///|
test "nlp: ngrams too few tokens" {
  let tokens = ["a"]
  let bigrams = ngrams(tokens, 2)
  assert_true(bigrams.length() == 0)
}

///|
test "nlp: char_ngrams" {
  let ngrams = char_ngrams("abc", 2)
  assert_true(ngrams.length() == 2)
  assert_true(ngrams[0] == "ab")
  assert_true(ngrams[1] == "bc")
}

///|
test "nlp: tfidf basic" {
  let docs : Array[Array[String]] = [
    ["apple", "banana", "apple"],
    ["banana", "cherry"],
    ["apple", "cherry", "date"],
  ]
  let (vectorizer, matrix) = fit_transform(docs)
  // Each document should have a non-zero vector
  assert_true(matrix.length() == 3)
  // "apple" appears in docs 0 and 2 but not 1, so its IDF should be higher
  assert_true(vectorizer.vocabulary.contains("apple"))
  assert_true(vectorizer.vocabulary.contains("banana"))
  assert_true(vectorizer.vocabulary.contains("cherry"))
  assert_true(vectorizer.vocabulary.contains("date"))
  // Vectors should be L2 normalized
  for d = 0; d < 3; d = d + 1 {
    let mut norm = 0.0
    for i = 0; i < matrix[d].length(); i = i + 1 {
      norm = norm + matrix[d][i] * matrix[d][i]
    }
    assert_true((norm - 1.0).abs() < 1.0e-10)
  }
}

///|
test "nlp: cosine similarity identical" {
  let a = [1.0, 2.0, 3.0]
  let b = [1.0, 2.0, 3.0]
  let sim = cosine_similarity(a, b)
  assert_true((sim - 1.0).abs() < 1.0e-10)
}

///|
test "nlp: cosine similarity orthogonal" {
  let a = [1.0, 0.0]
  let b = [0.0, 1.0]
  let sim = cosine_similarity(a, b)
  assert_true(sim.abs() < 1.0e-10)
}

///|
test "nlp: cosine similarity tfidf documents" {
  let docs : Array[Array[String]] = [
    ["apple", "banana"],
    ["apple", "banana"],
    ["cherry", "date"],
  ]
  let (_vectorizer, matrix) = fit_transform(docs)
  // Documents 0 and 1 are identical
  let sim_01 = cosine_similarity(matrix[0], matrix[1])
  assert_true((sim_01 - 1.0).abs() < 1.0e-10)
  // Documents 0 and 2 share no terms
  let sim_02 = cosine_similarity(matrix[0], matrix[2])
  assert_true(sim_02.abs() < 1.0e-10)
}

///|
test "nlp: to_lowercase" {
  assert_true(to_lowercase("HELLO") == "hello")
  assert_true(to_lowercase("Hello World") == "hello world")
  assert_true(to_lowercase("123ABC") == "123abc")
}

///|
test "nlp: trim" {
  assert_true(trim("  hello  ") == "hello")
  assert_true(trim("hello") == "hello")
  assert_true(trim("   ") == "")
  assert_true(trim("") == "")
}

///|
test "nlp: tokenize_with_stopwords" {
  let stop_words : Map[String, Unit] = Map([])
  stop_words["the"] = ()
  stop_words["a"] = ()
  stop_words["is"] = ()
  let tokens = tokenize_with_stopwords("the cat is a animal", true, stop_words)
  assert_true(tokens.length() == 2)
  assert_true(tokens[0] == "cat")
  assert_true(tokens[1] == "animal")
}
