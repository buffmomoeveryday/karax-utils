# fastKaraxRouter
## A blazing-fast, hash-based router library for Karax with compile-time route
## validation, duplicate detection, typed route parameter extraction, route-level
## and global navigation guards, and typed query helpers.

import router/types as routerTypes
import router/guards as routerGuards
import router/path as routerPath
import router/trie as routerTrie
import router/location as routerLocation
import router/query as routerQuery
import router/registration as routerRegistration
import router/macros as routerMacros
import router/lifecycle as routerLifecycle
import router/dispatch as routerDispatch

export
  routerTypes,
  routerGuards,
  routerPath,
  routerTrie,
  routerLocation,
  routerQuery,
  routerRegistration,
  routerMacros,
  routerLifecycle,
  routerDispatch
