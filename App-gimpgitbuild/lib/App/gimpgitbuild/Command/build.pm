package App::gimpgitbuild::Command::build;

use strict;
use warnings;
use autodie;
use 5.014;

use App::gimpgitbuild -command;

use File::Which qw/ which /;
use Path::Tiny qw/ path cwd /;

use App::gimpgitbuild::API::GitBuild ();
use Git::Sync::App                   ();

sub _mode
{
    my $self = shift;

    if (@_)
    {
        $self->{_mode} = shift;
    }

    return $self->{_mode};
}

sub _api_obj
{
    my $self = shift;

    if (@_)
    {
        $self->{_api_obj} = shift;
    }

    return $self->{_api_obj};
}

sub _process_executor
{
    my $self = shift;

    if (@_)
    {
        $self->{_process_executor} = shift;
    }

    return $self->{_process_executor};
}

sub description
{
    return "build gimp from git";
}

sub abstract
{
    return shift->description();
}

sub opt_spec
{
    return ( [ "mode=s", "Mode (e.g: \"clean\")" ],
        [ "process-exe=s", qq#Process executor (= "sh" or "perl")#, ] );

=begin foo
    return (
        [ "output|o=s", "Output path" ],
        [ "title=s",    "Chart Title" ],
        [ 'exec|e=s@',  "Execute command on the output" ]
    );
=end foo

=cut

}

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

sub _check
{
    return ( length( $ENV{SKIP_CHECK} ) ? "true" : "make check" );
}

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

my $PAR_JOBS = ( $ENV{GIMPGITBUILD__PAR_JOBS_FLAGS} // '-j4' );

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
                if ( not chdir($dirname) )
                {
                    die qq#Failed changing directory to "$dirname"!#;
                }
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
    chdir($orig_cwd);
    return;
}

sub _which_xvfb_run
{
    my $path = which('xvfb-run');
    if ( not defined($path) )
    {
        die
"Cannot find xvfb-run ! It is required for tests to succeed: see https://gitlab.gnome.org/GNOME/gimp/-/issues/2884";
    }
    return;
}

sub _ascertain_lack_of_gtk_warnings
{
    my $path = which('gvim');
    if ( defined($path) )
    {
        my $stderr = `"$path" -u NONE -U NONE -f /dev/null +q 2>&1`;
        if ( $stderr =~ /\S/ )
        {
            die
"There may be gtk warnings (e.g: in KDE Plasma 5 on Fedora 32 ). Please fix them.";
        }
    }
    return;
}

sub execute
{
    my ( $self, $opt, $args ) = @_;

    my $mode = ( $opt->{mode} || 'build' );
    if ( not( ( $mode eq 'clean' ) or ( $mode eq 'build' ) ) )
    {
        die "Unsupported mode '$mode'!";
    }

    my $_process_executor = ( $opt->{process_exe} || 'perl' );
    if (
        not(   ( $_process_executor eq 'sh' )
            or ( $_process_executor eq 'perl' ) )
        )
    {
        die "Unsupported process-exe '$_process_executor'!";
    }
    $self->_process_executor($_process_executor);

    my $fh  = \*STDIN;
    my $obj = App::gimpgitbuild::API::GitBuild->new;
    $self->_api_obj($obj);

    my $HOME = $obj->home_dir;
    my $env  = $obj->new_env;
    $ENV{PATH}            = $env->{PATH};
    $ENV{PKG_CONFIG_PATH} = $env->{PKG_CONFIG_PATH};
    $ENV{XDG_DATA_DIRS}   = $env->{XDG_DATA_DIRS};
    _which_xvfb_run();
    _ascertain_lack_of_gtk_warnings();
    $self->_mode($mode);

    my $GNOME_GIT = 'https://gitlab.gnome.org/GNOME';
    $self->_git_build(
        {
            id                  => "babl",
            git_checkout_subdir => "babl/git/babl",
            url                 => "$GNOME_GIT/babl",
            prefix              => $obj->babl_p,
            use_meson           => 1,
        }
    );
    $self->_git_build(
        {
            id                  => "gegl",
            git_checkout_subdir => "gegl/git/gegl",
            url                 => "$GNOME_GIT/gegl",
            prefix              => $obj->gegl_p,
            use_meson           => 1,
        }
    );
    $self->_git_build(
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
    $self->_git_build(
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

    $self->_git_build(
        {
            id                   => "gimp",
            extra_configure_args => [ qw# --enable-debug #, ],
            git_checkout_subdir  => "git/gimp",
            url                  => "$GNOME_GIT/gimp",
            prefix               => $obj->gimp_p,
            use_meson            => $BUILD_GIMP_USING_MESON,
            on_failure           => sub {
                my ($args) = @_;
                my $Err = $args->{exception};
                if ( !$BUILD_GIMP_USING_MESON )
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

    use Term::ANSIColor qw/ colored /;
    print colored( [ $ENV{HARNESS_SUMMARY_COLOR_SUCCESS} || 'bold green' ],
        "\n== Success ==\n\n" );
    return;
}

1;

__END__

=head1 NAME

gimpgitbuild build - command line utility to automatically build GIMP and its dependencies from git.

=cut
