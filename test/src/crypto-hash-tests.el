;;; crypto-hash-tests.el --- known-vector correctness for md5/sha1/sha256/sha512  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Free Software Foundation, Inc.

;; These tests pin the output of Emacs's cryptographic hashes to known
;; published vectors (FIPS 180 / RFC 1321) for the empty string, a short
;; input, a single-block-length input, and a multi-block input.  They
;; guard against silent regressions if the underlying hash implementation
;; is ever changed (for example a future native-Zig replacement for
;; gnulib's lib/md5.c / lib/sha*.c), which the generic (md5 ...) tests in
;; the wider suite would NOT catch (they only need a consistent hash, not
;; a correct one).

(require 'ert)

(defconst crypto-hash-tests--fips56
  "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  "56-byte input from the FIPS 180 test suite (single-block boundary).")

(ert-deftest crypto-hash-md5 ()
  (should (equal (md5 "")                       "d41d8cd98f00b204e9800998ecf8427e"))
  (should (equal (md5 "abc")                    "900150983cd24fb0d6963f7d28e17f72"))
  (should (equal (md5 crypto-hash-tests--fips56) "8215ef0796a20bcaaae116d3876c664a"))
  (should (equal (md5 (make-string 100 ?a))     "36a92cc94a9e0fa21f625f8bfb007adf")))

(ert-deftest crypto-hash-sha1 ()
  (should (equal (secure-hash 'sha1 "")                       "da39a3ee5e6b4b0d3255bfef95601890afd80709"))
  (should (equal (secure-hash 'sha1 "abc")                    "a9993e364706816aba3e25717850c26c9cd0d89d"))
  (should (equal (secure-hash 'sha1 crypto-hash-tests--fips56) "84983e441c3bd26ebaae4aa1f95129e5e54670f1"))
  (should (equal (secure-hash 'sha1 (make-string 100 ?a))     "7f9000257a4918d7072655ea468540cdcbd42e0c")))

(ert-deftest crypto-hash-sha256 ()
  (should (equal (secure-hash 'sha256 "")                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
  (should (equal (secure-hash 'sha256 "abc")                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
  (should (equal (secure-hash 'sha256 crypto-hash-tests--fips56) "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"))
  (should (equal (secure-hash 'sha256 (make-string 100 ?a))     "2816597888e4a0d3a36b82b83316ab32680eb8f00f8cd3b904d681246d285a0e")))

(ert-deftest crypto-hash-sha512 ()
  (should (equal (secure-hash 'sha512 "abc")                "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"))
  (should (equal (secure-hash 'sha512 (make-string 100 ?a)) "70ff99fd241905992cc3fff2f6e3f562c8719d689bfe0e53cbc75e53286d82d8767aed0959b8c63aadf55b5730babee75ea082e88414700d7507b988c44c47bc")))
