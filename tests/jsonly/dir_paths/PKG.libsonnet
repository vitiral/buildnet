
local paths = [
    "./README.txt",
    "./script.py",
    "./dir/",
];


function(wake)
    local digest = import "./.wakeDigest.json";
    local pkgVer = wake.pkgVer(null, "dir_paths", "0.1.0", digest);

    wake.pkg(
        pkgVer = pkgVer,
        paths = paths,
        depsReq = wake.depsReq(
            unrestricted={
                "pytest": wake.pkgReq(null, "pYpI", "pytest@>=5.0.0"),
            },
        ),
    )

