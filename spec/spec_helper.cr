require "spec"
require "wiretap"
require "liaison"

# Live specs record once against a real server and replay from disk thereafter.
# Transcripts are committed: they are what makes the suite offline and
# deterministic for everyone who did not record them.
Wiretap.configure do |c|
  c.transcript_dir = "spec/transcripts"

  # `:once` only under `RECORD=1`, and never in CI. Otherwise a missing
  # transcript fails the run instead of quietly reaching for the network —
  # which on the paid endpoints would also be a bill.
  #
  # Compared rather than `try`ed: `ENV["RECORD"]?.try` yields nil when the
  # variable is unset, which is falsy, which would record on exactly the plain
  # run this is meant to protect.
  never_record = ENV["CI"]? || ENV["RECORD"]? != "1"
  c.record_mode = never_record ? :none : :once

  # Minted call identifiers carry a timestamp and a process-wide counter —
  # `mc_<epoch-ms>_<counter>` — so the same body can never digest identically
  # twice, and any transcript containing a tool call would be unreplayable as
  # recorded.
  #
  # Relabelled by first-occurrence order within each body, not merely stripped:
  # identifiers only have to be unique *within a session*, so what must match
  # between record and replay is which occurrences share an identifier, not
  # what the identifier's literal value was. A regex that kept the counter
  # digits looked like it satisfied this but didn't — the counter is
  # process-wide, so its value depends on how many identifiers every *other*
  # example minted first, which depends on spec execution order, which is not
  # guaranteed identical across platforms.
  #
  # This normalization is a pure function of one body's own content, so it
  # stays stable across platforms regardless of spec execution order.
  #
  # **No transcript here needs it yet** — this CLI is text-only, so none of the
  # six carries a minted identifier. It is configured anyway because it is not
  # retroactive: `Transcript#find_interaction` compares against `body_digest`
  # as stored, frozen at record time under whatever `normalize_body` was in
  # effect then, and never recomputes it. Adding this function *after* tool
  # execution records its first transcripts would invalidate them and cost a
  # re-record; adding it before costs nothing.
  c.normalize_body = ->(body : String) {
    seen = {} of String => Int32
    body.gsub(/mc_\d+_\d+/) { |match| "mc_MINTED_#{seen[match] ||= seen.size}" }
  }
end

# Green is not the same as replayed.
#
# Under `:once` a missing transcript is recorded rather than failed, so a suite
# can pass while asserting against a recording the code under test made seconds
# earlier.
#
# `verify!` raises if anything was recorded, which makes the distinction
# visible. Set `RECORD=1` for the runs where recording is the point — cutting a
# new transcript, or re-cutting one a deliberate request change invalidated.
Spec.after_suite { Wiretap.verify! unless ENV["RECORD"]? }

# Shorthand shared by every spec file. Declared once here rather than in each
# file, since specs reopen the same namespace and a repeated `alias` is a
# redefinition error.
alias M = Liaison::MPSH
