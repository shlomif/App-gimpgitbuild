# ABSTRACT: gimp build
package App::gimpgitbuild;

use strict;
use warnings;

use App::Cmd::Setup -app;

1;

__END__

=head1 NAME

App-gimpgitbuild - build GIMP from git

=head1 SYNOPSIS

    gimpgitbuild build

=head1 DESCRIPTION

gimpgitbuild is a command line utility to automatically build
L<GIMP|https://www.gimp.org/> (= the "GNU Image Manipulation Program")
and some of its dependencies from its version control git repositories:
L<https://developer.gimp.org/git.html> .

Use it only if your paths and environment does not contain too many
nasty characters because we interpolate strings into the shell a lot.

So far, it is quite opinionated, but hopefully we'll allow for better
customization using L<https://en.wikipedia.org/wiki/Environment_variable>
in the future.

=head2 HISTORY

This utility evolved from an L<old bash version|https://github.com/shlomif/shlomif-computer-settings/blob/db468a5d6190bce053af1621b30e7dfd673be43f/shlomif-settings/build-scripts/build/gimp-git-all-deps.bash>
and a L<rewrite in perl 5|https://github.com/shlomif/shlomif-computer-settings/blob/master/shlomif-settings/build-scripts/build/gimp-git-all-deps.pl> .

=head1 SEE ALSO

=over 4

=item * L<https://www.gimp.org/>

=back

=cut
