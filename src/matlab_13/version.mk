NAME    = matlab_13
PKGROOT = /opt/matlab/$(VERSION)
VERSION = 2014b
RELEASE = 1
RPM.EXTRAS = "Autoprov: 0"
RPM.EXTRAS = AutoReq:No
RPM.EXTRAS     = %define _\_os\_install_post %{nil}
