// -*- coding: utf-8 -*-
// Copyright (C) 2019 Rett Berg <github.com/vitiral>
//
// The source code is Licensed under either of
//
// * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
//   http://www.apache.org/licenses/LICENSE-2.0)
// * MIT license ([LICENSE-MIT](LICENSE-MIT) or
//   http://opensource.org/licenses/MIT)
//
// at your option.
//
// Unless you explicitly state otherwise, any contribution intentionally submitted
// for inclusion in the work by you, as defined in the Apache-2.0 license, shall
// be dual licensed as above, without any additional terms or conditions.

local C = (import 'wakeConstants.json');

C {
  local wake = self
  ,
  local U = wake.util
  ,
  local _P = wake._private

  ,
  // The package's namespace and name.
  pkgName(namespace, name):
    local namespaceStr = U.stringDefault(namespace);
    local namespaceLen = std.length(namespaceStr);

    assert namespaceLen == 0 || namespaceLen > 3 : 'namespace length must be > 3';
    assert !U.hasSep(namespaceStr) : "namespace must not contain '#'";
    assert std.length(name) > 3 : 'name length must be > 3';
    assert !U.hasSep(name) : "name must not contain '#'";

    std.join(C.WAKE_SEP, [
      namespaceStr,
      name,
    ])

  ,
  // Specifies what versions of a package are required using a semver.
  pkgReq(namespace, name, semver=null): {
    local semverStr = U.stringDefault(semver),

    assert !U.hasSep(semverStr) : "semver must not contain '@'",

    result: std.join(C.WAKE_SEP, [
      wake.pkgName(namespace, name),
      semverStr,
    ]),
  }.result

  ,
  // An exact version of a pkgName, including the digest.
  pkgVer(namespace, name, version, digest):
    assert std.isString(digest) : 'digest must be a string';
    // Note: the version must be an exact semver, but is checked later.
    std.join(C.WAKE_SEP, [
      wake.pkgName(namespace, name),
      version,
      digest,
    ])

  ,
  // Declare the root (application) package.
  pkgRoot(
    // The package itself
    pkg,

    // The pkgManager override to use.
    pkgManager=null,

    // Any global dependencies (i.e. compiler versions)
    global=null,

    // A pkgName/value pair of locked dependencies.
    //
    // The value must be one of:
    //   - a pkgVer
    //   - a pathRef with `ref=wake.ROOT`.
    locked=null,
  ):
    assert U.isPkg(pkg) : 'pkg must be a package.';
    {
      pkg: pkg,
      pkgManager: pkgManager,
      global: global,
      locked: locked,
    }


  ,
  // Declare a pkg (in PKG.libsonnet)
  pkg(
    pkgVer,

    // Description and other metadata regarding the origin of the package.
    pkgOrigin=null,

    // Local paths (files or dirs) this pkg depends on for building.
    paths=null,

    // Requirements for packages that this pkg depends on.
    depsReq=null,

    // Function which returns the export of this pkg.
    export=null,
  ): {
    [C.F_TYPE]: C.T_PKG,
    [C.F_STATE]: C.S_DECLARED,
    pkgVer: pkgVer,
    pkgOrigin: pkgOrigin,
    paths: U.arrayDefault(paths),
    depsReq: U.objDefault(depsReq),

    // lazy functions
    exportFn:: export,
  }

  ,
  // Declare dependency requirements for a package.
  depsReq(
    unrestricted=null,
    restricted=null,
    restrictedMajor=null,
    restrictedMinor=null,
    global=null,
  ): {
    unrestricted: U.objDefault(unrestricted),
    restricted: U.objDefault(restricted),
    restrictedMajor: U.objDefault(restrictedMajor),
    restrictedMinor: U.objDefault(restrictedMinor),
    global: U.objDefault(global),
  }

  ,
  // Declare how to build a module.
  module(
    pkg,
    modules,
    reqFsEntries=null,
    export=null,
    exec=null,
    origin=null,
  ): null  // TODO

  ,
  // Reference a path from within a pkg or module.
  pathRef(
    // A pkg or module to reference.
    ref,

    // The local path within the ref
    path,
  ): {
    assert U.isAtLeastDefined(ref) : 'ref must be defined',

    local vals = if U.isPkg(ref) then
      { type: C.T_PATH_REF_PKG, id: ref.pkgVer }
    else if ref == C.ROOT then
      C.ROOT
    else
      assert false : 'ref must be a pkg or a module.';
      null,

    [C.F_TYPE]: vals.type,
    [C.F_STATE]: C.S_DEFINED,
    ref: vals.id,
    path: path,
  }

  ,
  // Specify a wasi executable and the jsh params and inputs.
  exec(pathRef, params=null, inputs=null): {
    assert U.isPathRef(pathRef) : 'pathRef is wrong type',

    [C.F_TYPE]: C.T_EXEC,
    pathRef: pathRef,
    params: params,
    inputs: inputs,
  }

  ,
  _private: {
    local P = self

    ,
    // Looks up all items in the dependency tree
    lookupDeps(requestingPkgVer, depsReq):
      local lookupPkg = function(requestingPkgVer, category, pkgReq)
        local pkgKey = std.join(C.WAKE_SEP, [
          requestingPkgVer,
          pkgReq,
        ]);

        P.pkgsDefined[pkgKey];

      // Lookup all packages in deps
      local lookupPkgs = function(category, depPkgs) {
        [k]: lookupPkg(requestingPkgVer, category, depPkgs[k])
        for k in std.objectFields(depPkgs)
      };

      // Return the looked up dependencies
      {
        unrestricted: lookupPkgs('unrestricted', depsReq.unrestricted),
        restricted: lookupPkgs('restricted', depsReq.restricted),
        restrictedMajor: lookupPkgs('restrictedMajor', depsReq.restrictedMajor),
        restrictedMinor: lookupPkgs('restrictedMinor', depsReq.restrictedMinor),
        global: lookupPkgs('global', depsReq.global),
      }

    ,
    // Resolve the dependencies for all sub pkgs
    recursePkgResolve(wake, pkg):
      assert U.isPkg(pkg) : 'Not a pkg: %s' % [pkg];
      local requestingPkgVer = pkg.pkgVer;

      // Note: lvl is the "restriction level"
      local lookupPkg = function(lvl, pkgReq)
        assert std.isString(lvl);
        assert std.isString(pkgReq);

        local pkgKey = std.join(C.WAKE_SEP, [
          requestingPkgVer,
          pkgReq,
        ]);

        // NOTE: wake._private.pkgsDefined is **injected** by
        // wake/runWakeExport.jsonnet
        assert pkgKey in P.pkgsDefined : 'pkgKey=%s not found' % [pkgKey];

        local result = P.pkgsDefined[pkgKey](wake);
        assert U.isPkg(result) : 'lookupPkg result is not a package';
        result

      ;
      local lookupPkgs = function(lvl, pkgs)
        assert std.isString(lvl);
        assert std.isObject(pkgs) : '%s not object: %s' % [lvl, pkgs];
        {
          [k]: lookupPkg(lvl, pkgs[k])
          for k in std.objectFields(pkgs)
        }

      ;
      local depsShallow = {
        [lvl]: lookupPkgs(lvl, pkg.depsReq[lvl])
        for lvl in std.objectFields(pkg.depsReq)
      }

      ;
      local recurseMapResolve = function(pkgs) {
        [k]: P.recursePkgResolve(wake, pkgs[k])
        for k in std.objectFields(pkgs)
      }

      ;
      pkg {
        local this = self

        ,
        deps: {
          [lvl]: recurseMapResolve(depsShallow[lvl])
          for lvl in std.objectFields(depsShallow)
        },
      }

    ,
    // Note: pkg must have had recursePkgResolve called on it
    recurseCallExport(wake, pkg):
      local recurseMapExport = function(pkgs) {
        [k]: P.recurseCallExport(wake, pkgs[k])
        for k in std.objectFields(pkgs)
      }

      ;
      pkg {
        local this = self

        ,
        deps: {
          [lvl]: recurseMapExport(pkg.deps[lvl])
          for lvl in std.objectFields(pkg.deps)
        },

        export: if pkg.exportFn == null then
          null
        else
          pkg.exportFn(wake, this),
      },

    // , simplify(pkg): {
    //     [C.F_TYPE]: pkg[C.F_TYPE],
    //     [C.F_STATE]: pkg[C.F_STATE],
    //     pkgVer: pkg.pkgVer,

    //     local getIdOrUnresolved = function(dep)
    //         if U.isUnresolved(dep) then
    //             dep
    //         else
    //             dep.pkgVer,

    //     pathsDef: pkg.pathsDef,
    //     paths: pkg.paths,
    //     # FIXME: pathsReq
    //     pkgs: {
    //         [dep]: getIdOrUnresolved(pkg.pkgs[dep])
    //         for dep in std.objectFields(pkg.pkgs)
    //     },
    //     export: pkg.export,
    // }

    // , recurseSimplify(pkg):
    //     if U.isUnresolved(pkg) then
    //         [pkg]
    //     else
    //         local simpleDeps = [
    //             P.recurseSimplify(pkg.pkgs[dep])
    //             for dep in std.objectFields(pkg.pkgs)
    //         ];
    //         [P.simplify(pkg)] + std.flattenArrays(simpleDeps)
  }

  ,
  util: {
    // Wake typecheck functions
    isWakeObject(obj):
      std.isObject(obj)
      && (C.F_TYPE in obj)

    ,
    isErr(obj):
      U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_ERR

    ,
    isPkg(obj):
      U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_PKG

    ,
    // Wake status-check functions.
    isUnresolved(obj):
      U.isWakeObject(obj)
      && obj[C.F_STATE] == C.S_UNRESOLVED

    ,
    isDeclared(obj):
      U.isWakeObject(obj)
      && obj[C.F_STATE] == C.S_DECLARED

    ,
    isDefined(obj):
      U.isWakeObject(obj)
      && obj[C.F_STATE] == C.S_DEFINED

    ,
    isAtLeastDefined(obj):
      U.isDefined(obj)

    ,
    isPathRef(obj):
      U.isWakeObject(obj) && (
        obj[C.F_TYPE] == C.T_PATH_REF_PKG
        || obj[C.F_TYPE] == C.T_PATH_REF_MODULE
      )

    ,
    isExec(obj):
      U.isWakeObject(obj)
      && obj[C.F_TYPE] == C.T_EXEC

    ,
    isExecLocal(obj):
      U.isExec(obj) && obj.container == C.EXEC_LOCAL

    ,
    hasSep(s): U.containsChr(C.WAKE_SEP, s)

    ,
    // General Helpers
    boolToInt(bool): if bool then 1 else 0

    ,
    containsChr(c, str): !(std.length(std.splitLimit(str, c, 1)) == 1)

    ,
    // Retrieve a value from an object at an arbitrary depth.
    getKeys(obj, keys, cur_index=0):
      local value = obj[keys[cur_index]];
      local new_index = cur_index + 1;
      if new_index == std.length(keys) then
        value
      else
        U.getKeys(value, keys, new_index)

    ,
    // Default functions return empty containers on null
    arrayDefault(arr): if arr == null then [] else arr
    ,
    objDefault(obj): if obj == null then {} else obj
    ,
    stringDefault(s): if s == null then '' else s,
  },
}
