## Global runtime location and query cache (current route session).

import std/tables

import router/types

var
  currentRoutePath*: string = "/"
  currentRawHash*: string = ""
  currentRawQuery*: string = ""
  cachedQuerySource*: string = "\x00"
  cachedQueryTable*: Table[string, seq[string]]
  activeRouter*: KaraxRouter = nil
