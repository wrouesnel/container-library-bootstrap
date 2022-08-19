# Container Library Bootstrap

Script and tool to use `skopeo` to initialize a library of docker images. This is frequently necessary when interacting
with prviate image registry's in order to provide a solid base of trusted images which can be used to derive further
ones.

Note: you will probably not want to use these directly, but rather source them into an additional set of images which
have had certificate authorities injected properly.