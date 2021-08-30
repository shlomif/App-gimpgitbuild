package App::gimpgitbuild::API::Worker;

use strict;
use warnings;
use 5.014;

use Moo;

use Path::Tiny qw/ path cwd /;
use Git::Sync::App                   ();
use App::gimpgitbuild::API::GitBuild ();

has '_api_obj' => (
    is      => 'rw',
    default => sub { return App::gimpgitbuild::API::GitBuild->new(); }
);
has '_mode'             => ( is => 'ro', required => 1, );
has '_override_mode'    => ( is => 'rw', default  => "", );
has '_process_executor' => ( is => 'ro', required => 1, );

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
    my $extra_meson_args     = ( $args->{extra_meson_args}     // [] );
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
    my $clean_install = ( $self->_override_mode() eq "clean_install" );
    my $PERL_EXECUTE =
        ( $clean_install or $self->_process_executor() eq 'perl' );
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

    my $prefix = $args->{prefix};

    if ($clean_install)
    {
        $shell_cmd->(qq#rm -fr "$prefix"#)->();
        return;
    }

    my $gen_meson_build_cmds = sub {
        return [
            $shell_cmd->(qq#mkdir -p "$BUILD_DIR"#),
            $chdir_cmd->($BUILD_DIR),
            $shell_cmd->(
qq#meson --prefix="$prefix" $UBUNTU_MESON_LIBDIR_OVERRIDE @{$extra_meson_args} ..#
            ),
            $shell_cmd->(qq#ninja $PAR_JOBS#),
            $shell_cmd->(qq#ninja $PAR_JOBS test#),
            $shell_cmd->(qq#ninja $PAR_JOBS install#),
        ];
    };
    my $gen_autoconf_build_cmds = sub {
        return [
            $shell_cmd->(qq#NOCONFIGURE=1 ./autogen.sh#),
            $shell_cmd->(qq#mkdir -p "$BUILD_DIR"#),
            $chdir_cmd->($BUILD_DIR),
            $shell_cmd->(
                qq#../configure @{$extra_configure_args} --prefix="$prefix"#),
            $shell_cmd->(qq#make $PAR_JOBS#),
            $shell_cmd->(qq#@{[_check()]}#),
            $shell_cmd->(qq#make install#),
        ];
    };
    my $gen_clean_mode_cmds =
        sub { return [ $shell_cmd->(qq#git clean -dxf .#), ]; };
    my $commands_gen = (
        ( $self->_mode() eq 'clean' ) ? $gen_clean_mode_cmds
        : (
              $args->{use_meson} ? $gen_meson_build_cmds
            : $gen_autoconf_build_cmds
        )
    );
    my $sync_cmd = $self->_git_sync( { branch => $args->{branch}, } );
    my @commands = (
        $chdir_cmd->($git_co),
        $shell_cmd->(qq#git checkout "$args->{branch}"#),
        $shell_cmd->(qq#( $args->{tag} || $sync_cmd )#),
        @{ $commands_gen->() },
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

sub _get_gnome_git_url
{
    my ( $self, $proj ) = @_;
    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';

    return "${GNOME_GIT}/${proj}.git/";
}

sub _run_all
{
    my ($worker) = @_;
    my $obj = $worker->_api_obj();
    $worker->_git_build(
        {
            id                  => "babl",
            git_checkout_subdir => "babl/git/babl",
            url                 => $worker->_get_gnome_git_url("babl"),
            prefix              => $obj->babl_p,
            use_meson           => 1,
        }
    );
    $worker->_git_build(
        {
            id                  => "gegl",
            git_checkout_subdir => "gegl/git/gegl",
            extra_meson_args    => [ qw# -Dlua=disabled #, ],
            url                 => $worker->_get_gnome_git_url("gegl"),
            prefix              => $obj->gegl_p,
            use_meson           => 1,
        }
    );
    $worker->_git_build(
        {
            id                  => "libmypaint",
            git_checkout_subdir => "libmypaint/git/libmypaint",
            url                 => "https://github.com/mypaint/libmypaint.git",
            prefix              => $obj->mypaint_p,
            use_meson           => 0,
            branch              => "v1.6.1",
            tag                 => "true",
        }
    );
    $worker->_git_build(
        {
            id                  => "mypaint-brushes",
            git_checkout_subdir => "libmypaint/git/mypaint-brushes",
            url       => "https://github.com/Jehan/mypaint-brushes.git",
            prefix    => $obj->mypaint_p,
            use_meson => 0,
            branch    => "v1.3.x",
        }
    );

    my $KEY                    = 'GIMPGITBUILD__BUILD_GIMP_USING_MESON';
    my $BUILD_GIMP_USING_MESON = ( exists( $ENV{$KEY} ) ? $ENV{$KEY} : 1 );

    $worker->_git_build(
        {
            id                   => "gimp",
            extra_configure_args => [ qw# --enable-debug --with-lua=no #, ],
            extra_meson_args     => [ qw# -Dlua=false #, ],
            git_checkout_subdir  => "git/gimp",
            url                  => $worker->_get_gnome_git_url("gimp"),
            prefix               => $obj->gimp_p,
            use_meson            => $BUILD_GIMP_USING_MESON,
            on_failure           => sub {
                my ($args) = @_;
                my $Err = $args->{exception};
                if (   ( $worker->_mode() eq 'clean' )
                    or ( !$BUILD_GIMP_USING_MESON ) )
                {
                    die $Err;
                }
                STDERR->print( $Err, "\n" );
                STDERR->print(<<"EOF");
Meson-using builds of GIMP are known to be error prone. Please try setting
the "$KEY" environment variable to "0", and run gimpgitbuild again, e.g using:

    export $KEY="0"

EOF
                die "Meson build failure";
            },
        }
    );
    return;
}

sub _run_the_mode_on_all_repositories
{
    my ($worker) = @_;

    if ( $worker->_mode() eq 'build' )
    {
        $worker->_override_mode("clean_install");
        $worker->_run_all();
    }
    $worker->_override_mode("");
    $worker->_run_all();

    return;
}

1;

__END__

=head1 NAME

App::gimpgitbuild::API::Worker - common API

=head1 METHODS

=cut
