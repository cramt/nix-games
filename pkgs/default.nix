# Every game lives in its own directory here and gets one line below.
#
# Kept as a plain attrset (rather than an auto-discovering import-tree) so it
# doubles as the overlay body: `pkgs.legends-of-runeterra` works for anyone who
# adds this flake's overlay, with no flake-parts machinery leaking into it.
{pkgs}: {
  legends-of-runeterra = pkgs.callPackage ./legends-of-runeterra {};
}
