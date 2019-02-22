// instantiate the wake library and user overrides.
local wakelib = import "../../../wake/lib/wake.libsonnet";
local user = (import "../../../wake/user.libsonnet")(wakelib);
local pkgsDef = (import "../_wake_/pkgDefs.libsonnet");

local wake =
    wakelib    // the base library
    + pkgsDef  // (computed last cycle) defined pkgs
    + user;    // user settings

// instantiate and return the root pkg
local pkg_fn = (import "../PKG.libsonnet");
local pkg = pkg_fn(wake);

{
    wake: wake,
    root: pkg,
}
