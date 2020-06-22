package App::gimpgitbuild::API::Worker;

use strict;
use warnings;
use 5.014;

use Moo;

use Path::Tiny qw/ path cwd /;

has '_api_obj'          => ( is => 'rw' );
has '_mode'             => ( is => 'rw' );
has '_process_executor' => ( is => 'rw' );

sub _do_system
{
    my ($args) = @_;

    my $cmd = $args->{cmd};
    print "Running [@$cmd]\n";
    if ( system(@$cmd) )
    {
        die "Running [@$cmd] failed!";
    }
}

my $PAR_JOBS = ( $ENV{GIMPGITBUILD__PAR_JOBS_FLAGS} // '-j4' );
my $skip_builds_re;

BEGIN
{
    my $KEY = "GIMPGITBUILD__SKIP_BUILDS_RE";
    if ( exists $ENV{$KEY} )
    {
        my $re_str = $ENV{$KEY};
        $skip_builds_re = qr/$re_str/;
    }
}
my $BUILD_DIR = ( $ENV{GIMPGITBUILD__MESON_BUILD_DIR}
        // "to-del--gimpgitbuild--build-dir" );

# See:
# https://github.com/libfuse/libfuse/issues/212
# Ubuntu/etc. places it under $prefix/lib/$arch by default.
my $UBUNTU_MESON_LIBDIR_OVERRIDE = "-D libdir=lib";

sub _check
{
    return ( length( $ENV{SKIP_CHECK} ) ? "true" : "make check" );
}

sub _git_sync
{
    my ( $self, $args ) = @_;
    return
qq#$^X -MGit::Sync::App -e "Git::Sync::App->new->run" -- sync origin "$args->{branch}"#;
}

sub _git_build
{
    my $self                 = shift;
    my $args                 = shift;
    my $orig_cwd             = cwd()->absolute();
    my $id                   = $args->{id};
    my $extra_configure_args = ( $args->{extra_configure_args} // [] );
    my $SHELL_PREFIX         = "set -e -x";

    if ( defined($skip_builds_re) and $id =~ $skip_builds_re )
    {
        return;
    }
    $args->{branch} //= 'master';
    $args->{tag}    //= 'false';

    my $git_co = (
        $args->{git_co} // (
                  $self->_api_obj()->base_git_clones_dir() . "/"
                . $args->{git_checkout_subdir}
        )
    );
    if ( !-e $git_co )
    {
        path($git_co)->parent->mkpath;
        _do_system( { cmd => [qq#git clone "$args->{url}" "$git_co"#] } );
    }

    my $_autodie_chdir = sub {
        my $dirname = shift;
        if ( not chdir($dirname) )
        {
            die qq#Failed changing directory to "$dirname"!#;
        }
        return;
    };
    my $shell_cmd = sub {
        return shift;
    };
    my $chdir_cmd = sub {
        return $shell_cmd->( qq#cd "# . shift(@_) . qq#"# );
    };
    my $PERL_EXECUTE = ( $self->_process_executor() eq 'perl' );
    if ($PERL_EXECUTE)
    {
        $shell_cmd = sub {
            my $cmd = shift;
            return sub {
                return _do_system(
                    {
                        cmd => ["$SHELL_PREFIX ; $cmd"],
                    }
                );
            };
        };
        $chdir_cmd = sub {
            my $dirname = shift;
            return sub {
                return $_autodie_chdir->($dirname);
            };
        };
    }

    my @meson_build_shell_cmd = (
        $shell_cmd->(qq#mkdir -p "$BUILD_DIR"#),
        $chdir_cmd->($BUILD_DIR),
        $shell_cmd->(
qq#meson --prefix="$args->{prefix}" $UBUNTU_MESON_LIBDIR_OVERRIDE ..#
        ),
        $shell_cmd->(qq#ninja $PAR_JOBS#),
        $shell_cmd->(qq#ninja $PAR_JOBS test#),
        $shell_cmd->(qq#ninja $PAR_JOBS install#)
    );
    my @autoconf_build_shell_cmd = (
        $shell_cmd->(qq#NOCONFIGURE=1 ./autogen.sh#),
        $shell_cmd->(qq#mkdir -p "$BUILD_DIR"#),
        $chdir_cmd->($BUILD_DIR),
        $shell_cmd->(
            qq#../configure @{$extra_configure_args} --prefix="$args->{prefix}"#
        ),
        $shell_cmd->(qq#make $PAR_JOBS#),
        $shell_cmd->(qq#@{[_check()]}#),
        $shell_cmd->(qq#make install#)
    );
    my @clean_mode_shell_cmd = ( $shell_cmd->(qq#git clean -dxf .#) );
    my $sync_cmd = $self->_git_sync( { branch => $args->{branch}, } );
    my @commands = (
        $chdir_cmd->($git_co),
        $shell_cmd->(qq#git checkout "$args->{branch}"#),
        $shell_cmd->(qq#( $args->{tag} || $sync_cmd )#),
        (
            ( $self->_mode() eq 'clean' ) ? @clean_mode_shell_cmd
            : (
                  $args->{use_meson} ? @meson_build_shell_cmd
                : @autoconf_build_shell_cmd
            )
        ),
    );

    my $run = sub {
        if ($PERL_EXECUTE)
        {
            foreach my $cb (@commands)
            {
                $cb->();
            }
            return;
        }
        my $aggregate_shell_command =
            "$SHELL_PREFIX ; " . join( " ; ", @commands );
        return _do_system(
            {
                cmd => [ $aggregate_shell_command, ]
            }
        );
    };

    my $on_failure = $args->{on_failure};

    if ( !$on_failure )
    {
        $run->();
    }
    else
    {
        eval { $run->(); };
        my $Err = $@;

        if ($Err)
        {
            $on_failure->( { exception => $Err, }, );
        }
    }
    $_autodie_chdir->($orig_cwd);
    return;
}

1;

__END__

=head1 NAME

App::gimpgitbuild::API::Worker - common API

=head1 METHODS

=cut
