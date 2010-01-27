package inc::MBX::Alien::FLTK::Base;
{
    use strict;
    use warnings;
    use Cwd;
    use Config qw[%Config];
    use File::Temp qw[tempfile];
    use File::Find qw[find];
    use Carp qw[carp];
    use base 'Module::Build';
    use lib '../../../../';
    use inc::MBX::Alien::FLTK::Utility
        qw[_o _a _path _dir _file _rel _abs _exe can_run];
    use lib _abs('.');

    sub fltk_dir {
        my ($self, $extra) = @_;
        $self->depends_on('extract_fltk');
        return
            _abs(_path($self->notes('extract'),
                       (      'fltk-'
                            . $self->notes('branch') . '-r'
                            . $self->notes('svn')
                       ),
                       $extra || ()
                 )
            );
    }

    sub archive {
        my ($self, $args) = @_;
        my $arch = $args->{'output'};
        my @cmd = ($self->notes('AR'), $arch, @{$args->{'objects'}});
        print STDERR "@cmd\n" if !$self->quiet;
        return inc::MBX::Alien::FLTK::Utility::run(@cmd) ? $arch : ();
    }

    sub test_exe {
        my ($self, $args) = @_;
        my ($exe,  @obj)  = $self->build_exe($args);
        return if !$exe;
        my $return = $self->do_system($exe);
        unlink $exe, @obj;
        return $return;
    }

    sub compile {
        my ($self, $args) = @_;
        local $^W = 0;
        local $self->cbuilder->{'quiet'} = 1;
        my $code = 0;
        if (!$args->{'source'}) {
            (my $FH, $args->{'source'}) = tempfile(
                                     undef, SUFFIX => '.cpp'    #, UNLINK => 1
            );
            syswrite($FH,
                     ($args->{'code'}
                      ? delete $args->{'code'}
                      : 'int main(){return 0;}'
                         )
                         . "\n"
            );
            close $FH;
            $code = 1;
        }
        my $obj = eval {
            $self->cbuilder->compile(
                  ($args->{'source'} !~ m[\.c$] ? ('C++' => 1) : ()),
                  source => $args->{'source'},
                  ($args->{'include_dirs'}
                   ? (include_dirs => $args->{'include_dirs'})
                   : ()
                  ),
                  ($args->{'extra_compiler_flags'}
                   ? (extra_compiler_flags => $args->{'extra_compiler_flags'})
                   : ()
                  )
            );
        };

        #unlink $args->{'source'} if $code;
        return if !$obj;
        return $obj;
    }

    sub link_exe {
        my ($self, $args) = @_;
        local $^W = 0;
        local $self->cbuilder->{'quiet'} = 1;
        my $exe = eval {
            $self->cbuilder->link_executable(
                                     objects            => $args->{'objects'},
                                     extra_linker_flags => (
                                         (  $args->{'extra_linker_flags'}
                                          ? $args->{'extra_linker_flags'}
                                          : ''
                                         )
                                         . ($args->{'source'} =~ m[\.c$] ? ''
                                            : ' -lsupc++'
                                         )
                                     )
            );
        };
        return if !$exe;
        return $exe;
    }

    sub build_exe {
        my ($self, $args) = @_;
        my $obj = $self->compile($args);
        return if !$obj;
        $args->{'objects'} = [$obj];
        my $exe = $self->link_exe($args);
        return if !$exe;
        return ($exe, $obj) if wantarray;
        unlink $obj;
        return $exe;
    }

    sub ACTION_copy_headers {
        my ($self) = @_;
        $self->depends_on('write_config_h');
        $self->depends_on('write_config_yml');
        my $headers_location
            = _path($self->fltk_dir(), $self->notes('headers_path'));
        my $headers_share = _path($self->base_dir(), qw[share include]);
        if (!chdir $headers_location) {
            printf 'Failed to cd to %s to copy headers', $headers_location;
            exit 0;
        }
        find {
            wanted => sub {
                return if -d;
                $self->copy_if_modified(
                                     from => $File::Find::name,
                                     to   => _path(
                                                 $headers_share,
                                                 $self->notes('headers_path'),
                                                 $File::Find::name
                                     )
                );
            },
            no_chdir => 1
            },
            '.';
        if (!chdir _path($self->fltk_dir())) {
            print 'Failed to cd to fltk\'s include directory';
            exit 0;
        }
        $self->copy_if_modified(from => 'config.h',
                                to   => _path($headers_share, 'config.h'));
        print "Copying headers to sharedir...\n" if !$self->quiet;
        if (!chdir $self->base_dir()) {
            printf 'Failed to return to %s', $self->base_dir();
            exit 0;
        }
        $self->notes(headers => $headers_share);
        return 1;
    }

    # Configure
    sub configure {
        my ($self, $args) = @_;
        $self->notes('define'        => {});
        $self->notes('cache'         => {});
        $self->notes('_a'            => $Config{'_a'});
        $self->notes('cxxflags'      => ' ');
        $self->notes('GL'            => ' ');
        $self->notes('include_dirs'  => {});
        $self->notes('library_paths' => {});

        # Let's get started
        {    # Both | All platforms
            print 'Locating library archiver... ';
            my $ar = can_run('ar');
            if (!$ar) {
                print "Could not find the library archiver, aborting.\n";
                exit 0;
            }
            $ar .= ' cr' . (can_run('ranlib') ? 's' : '');
            $self->notes('AR' => $ar);
            print "$ar\n";
        }
        {    # Both | All platforms
            print 'Checking whether byte ordering is big-endian... ';
            my $bigendian = ((unpack('h*', pack('s', 1)) =~ /01/) ? 1 : 0);
            $self->notes('define')->{'WORDS_BIGENDIAN'} = $bigendian;
            print $bigendian ? "yes\n" : "no\n";
        }
        {    # Both | All platforms
            for my $type (qw[short int long]) {
                printf 'Checking size of %s... ', $type;
                my $exe = $self->build_exe({code => <<"" });
static long int longval () { return (long int) (sizeof ($type)); }
static unsigned long int ulongval () { return (long int) (sizeof ($type)); }
#include <stdio.h>
#include <stdlib.h>
int main ( ) {
    if (((long int) (sizeof ($type))) < 0) {
        long int i = longval ();
        if (i != ((long int) (sizeof ($type))))
            return 1;
        printf ("%ld", i);
    }
    else {
        unsigned long int i = ulongval ();
        if (i != ((long int) (sizeof ($type))))
            return 1;
        printf ("%lu", i);
    }
    return 0;
}

                $self->notes('cache')->{'sizeof'}{$type} = $exe ? `$exe` : ();
                print((  $self->notes('cache')->{'sizeof'}{$type}
                       ? $self->notes('cache')->{'sizeof'}{$type}
                       : "unsupported"
                      )
                      . "\n"
                );
            }
            if ($self->notes('cache')->{'sizeof'}{'short'} == 2) {
                $self->notes('define')->{'U16'} = 'unsigned short';
            }
            if ($self->notes('cache')->{'sizeof'}{'int'} == 4) {
                $self->notes('define')->{'U32'} = 'unsigned';
            }
            else {
                $self->notes('define')->{'U32'} = 'unsigned long';
            }
            if ($self->notes('cache')->{'sizeof'}{'int'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned';
            }
            elsif ($self->notes('cache')->{'sizeof'}{'long'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned long';
            }
        }
        {    # Both | All platforms
            print
                'Checking whether the compiler recognizes bool as a built-in type... ';
            my $exe = $self->build_exe({code => <<'' });
#include <stdio.h>
#include <stdlib.h>
int f(int  x){printf ("int "); return 1;}
int f(char x){printf ("char"); return 1;}
int f(bool x){printf ("bool"); return 1;}
int main ( ) {
    bool b = true;
    return f(b);
}

            my $type = $exe ? `$exe` : 0;
            if ($type) { print "yes ($type)\n" }
            else {
                print "no\n";    # But we can pretend...
                $self->notes('cxxflags' => ' -Dbool=char -Dfalse=0 -Dtrue=1 '
                             . $self->notes('cxxflags'));
            }
        }
        {    # Both | All platforms | Standard headers/functions
            my @headers = qw[dirent.h sys/ndir.h sys/dir.h ndir.h];
            for my $header (@headers) { }
        HEADER: for my $header (@headers) {
                printf 'Checking for %s that defines DIR... ', $header;
                my $exe = $self->build_exe({code => sprintf <<'' , $header});
#include <stdio.h>
#include <sys/types.h>
#include <%s>
int main ( ) {
    if ( ( DIR * ) 0 )
        return 0;
    printf( "1" );
    return 0;
}

                if ($exe ? `$exe` : 0) {
                    print "yes ($header)\n";
                    my $define = uc 'HAVE_' . $header;
                    $define =~ s|[/\.]|_|g;
                    $self->notes('define')->{$define} = 1;
                    $self->notes('cache')->{'header_dirent'} = $header;
                    last HEADER;
                }
                else {
                    print "no\n";    # But we can pretend...
                }
            }
        }
        {   # Two versions of opendir et al. are in -ldir and -lx on SCO Xenix
            if ($self->notes('cache')->{'header_dirent'} eq 'dirent.h') {
                print 'Checking for library containing opendir... ';
            LIB: for my $lib ('', '-ldir', '-lx', '-lc') {
                    my $exe = $self->build_exe(
                                  {code => <<'', extra_linker_flags => $lib});
#include <stdio.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
#endif
char opendir ( );
int main () {
    return opendir ( );
    return 0;
}

                    if ($exe) {
                        if   ($lib) { print "$lib\n" }
                        else        { print "none required\n" }
                        $self->notes(
                             'ldflags' => " $lib " . $self->notes('ldflags'));
                        $self->notes('cache')->{'opendir_lib'} = $lib;
                        last LIB;
                    }
                }
                if (!defined $self->notes('cache')->{'opendir_lib'}) {
                    print "FAIL!\n";    # XXX - quit
                }
            }
        }
        {
            print 'Checking for scandir... ';
            if ($self->build_exe({code => <<''})) {
#include <stdio.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
#endif
/* Define scandir to an innocuous variant, in case <limits.h> declares scandir.
   For example, HP-UX 11i <limits.h> declares gettimeofday.  */
#define scandir innocuous_scandir
/* System header to define __stub macros and hopefully few prototypes,
    which can conflict with char scandir (); below.
    Prefer <limits.h> to <assert.h> if __STDC__ is defined, since
    <limits.h> exists even on freestanding compilers.  */
#ifdef __STDC__
# include <limits.h>
#else
# include <assert.h>
#endif
#undef scandir
/* Override any GCC internal prototype to avoid an error.
   Use char because int might match the return type of a GCC
   builtin and then its argument prototype would still apply.  */
#ifdef __cplusplus
extern "C"
#endif
char scandir ();
/* The GNU C library defines this for functions which it implements
    to always fail with ENOSYS.  Some functions are actually named
    something starting with __ and the normal name is an alias.  */
#if defined __stub_scandir || defined __stub___scandir
choke me
#endif
int main ( ) {
    return scandir ( );
    return 0;
}

                print "yes\n";
                $self->notes('define')->{'HAVE_POSIX'} = 1;
            }
            else { print "no\n" }
        }
        {
            last if !defined $self->notes('define')->{'HAVE_SCANDIR'};
            print 'Checking for a POSIX compatible scandir() prototype... ';
            if ($self->build_exe({code => <<''})) {
#include <stdio.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
#endif
#include <dirent.h>
int func (const char *d, dirent ***list, void *sort) {
    int n = scandir(d, list, 0, (int(*)(const dirent **, const dirent **))sort);
}
int main ( ) {
    return 0;
}

                print "yes\n";
                $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = 1;
            }
            else { print "no\n" }
        }
        {
            print "Checking string functions...\n";
            if (($self->notes('os') =~ m[^hpux$]i)
                && $self->notes('os_ver') == 1020)
            {   print
                    "\nNot using built-in snprintf function because you are running HP-UX 10.20\n";
                $self->notes('define')->{'HAVE_SNPRINTF'} = undef;
                print
                    "\nNot using built-in vnprintf function because you are running HP-UX 10.20\n";
                $self->notes('define')->{'HAVE_VNPRINTF'} = undef;
            }
            elsif (($self->notes('os') =~ m[^dec_osf$]i)
                   && $self->notes('os_ver') == 40)
            {   print
                    "\nNot using built-in snprintf function because you are running Tru64 4.0.\n";
                $self->notes('define')->{'HAVE_SNPRINTF'} = undef;
                print
                    "\nNot using built-in vnprintf function because you are running Tru64 4.0.\n";
                $self->notes('define')->{'HAVE_VNPRINTF'} = undef;
            }
        }
        {
            my %functions = (
                strdup      => 'HAVE_STRDUP',
                strcasecmp  => 'HAVE_STRCASECMP',
                strncasecmp => 'HAVE_STRNCASECMP',
                strlcat     => 'HAVE_STRLCRT',

                #strlcpy     => 'HAVE_STRLCPY'
            );
            for my $func (keys %functions) {
                printf 'Checking for %s... ', $func;
                my $obj = $self->compile({code => <<""});
/* Define $func to an innocuous variant, in case <limits.h> declares $func.
   For example, HP-UX 11i <limits.h> declares gettimeofday.  */
#define $func innocuous_$func
/* System header to define __stub macros and hopefully few prototypes,
    which can conflict with char $func (); below.
    Prefer <limits.h> to <assert.h> if __STDC__ is defined, since
    <limits.h> exists even on freestanding compilers.  */
#ifdef __STDC__
# include <limits.h>
#else
# include <assert.h>
#endif
#undef $func
/* Override any GCC internal prototype to avoid an error.
   Use char because int might match the return type of a GCC
   builtin and then its argument prototype would still apply.  */
#ifdef __cplusplus
extern "C"
#endif
char $func ();
/* The GNU C library defines this for functions which it implements
    to always fail with ENOSYS.  Some functions are actually named
    something starting with __ and the normal name is an alias.  */
#if defined __stub_$func || defined __stub___$func
choke me
#endif
int main ( ) {
    return $func ( );
    return 0;
}

                if ($obj) {
                    print "yes\n";
                    $self->notes('define')->{$functions{$func}} = 1;
                }
                else {
                    print "no\n";
                    $self->notes('define')->{$functions{$func}} = undef;
                }
            }
        }
        {
            $self->find_h('pthread.h');
            last if !defined $self->notes('define')->{'HAVE_PTHREAD_H'};
            print 'Testing pthread support... ';
            if ($self->assert_lib({headers => [qw[pthread.h]]})) {
                print "okay\n";
                $self->notes('define')->{'HAVE_PTHREAD'} = 1;
                last;
            }
            print "FAIL!\n";
        }
        {
            print 'Checking for library containing pow... ';
            my $_have_pow = '';
        LIB: for my $lib ('', '-lm') {
                my $exe = $self->build_exe(
                                  {code => <<'', extra_linker_flags => $lib});
#include <stdio.h>
#include <stdlib.h>
#ifdef __cplusplus
extern "C"
#endif
char pow ();
int main ( ) {
    printf ("1");
    return pow ();
    return 0;
}

                if ($exe && `$exe`) {
                    if   ($lib) { print "$lib\n" }
                    else        { print "none required\n" }
                    $self->notes(
                             'ldflags' => $self->notes('ldflags') . " $lib ");
                    $_have_pow = 1;
                    last LIB;
                }
            }
            if (!$_have_pow) {
                print "FAIL!\n";    # XXX - quit
            }
        }
        {
            $self->find_h('string.h');
            $self->find_h('strings.h');
            $self->find_h('sys/select.h');
            $self->find_h('png.h');
        }
        {
            print "Setting defaults...\n";
            print "    BORDER_WIDTH = 2\n";
            $self->notes('BORDER_WIDTH' => 2);
            print "    USE_COLORMAP = 1\n";
            $self->notes('USE_COLORMAP' => 1);
            print "    HAVE_GL_OVERLAY = 1\n";
            $self->notes('HAVE_GL_OVERLAY' => 'HAVE_OVERLAY');

=todo
        $self->notes(
            config => {
                __APPLE_QUARTZ__       => undef,                       # 1.3.x
                __APPLE_QD__           => undef,                       # 1.3.x
                USE_X11_MULTITHREADING => 0,                           # 2.0
                USE_XFT                => 0,                           # both
                USE_XCURSOR            => undef,
                USE_CAIRO              => $self->notes('use_cairo'),   # both
                USE_CLIPOUT            => 0,
                USE_XSHM               => 0,
                HAVE_XDBE              => 0,                           # both
                USE_XDBE               => 'HAVE_XDBE',                 # both
                USE_OVERLAY            => 0,
                USE_XINERAMA           => 0,
                USE_MULTIMONITOR       => 1,
                USE_STOCK_BRUSH        => 1,
                USE_XIM                => 1,
                HAVE_ICONV             => 0,
                USE_GL_OVERLAY            => 0,                        # 2.0
                USE_GLEW                  => 0,                        # 2.0
                HAVE_GLXGETPROCADDRESSARB => undef,                    # 1.3
                HAVE_VSNPRINTF   => 1,
                HAVE_SNPRINTF    => 1,
                HAVE_STRCASECMP  => undef,
                HAVE_STRDUP      => undef,
                HAVE_STRLCAT     => undef,
                HAVE_STRLCPY     => undef,
                HAVE_STRNCASECMP => undef,
                USE_POLL         => 0,                                # both
                HAVE_LIBPNG      => undef,
                HAVE_LIBZ        => undef,
                HAVE_LIBJPEG     => undef,
                HAVE_LOCAL_PNG_H => undef,
                HAVE_LIBPNG_PNG_H => undef,
                HAVE_LOCAL_JPEG_H => undef,
                HAVE_EXCEPTIONS      => undef,
                HAVE_DLOPEN          => 0,
                BOXX_OVERLAY_BUGS    => 0,
                SGI320_BUG           => 0,
                CLICK_MOVES_FOCUS    => 0,
                IGNORE_NUMLOCK       => 1,
                USE_PROGRESSIVE_DRAW => 1,
                HAVE_XINERAMA        => 0        # 1.3.x
            }
        );
=cut
        }
        return 1;
    }

    sub build_fltk {
        my ($self, $build) = @_;
        $self->quiet(1);
        $self->notes('libs' => []);
        my $libs = $self->notes('libs_source');
        for my $lib (sort { lc $a cmp lc $b } keys %$libs) {
            print "Building $lib...\n";
            if (!chdir _path($build->fltk_dir(), $libs->{$lib}{'directory'}))
            {   printf 'Cannot chdir to %s to build %s',
                    _path($build->fltk_dir(), $libs->{$lib}{'directory'}),
                    $lib;
                exit 0;
            }
            my @obj;
            for my $src (sort { lc $a cmp lc $b } @{$libs->{$lib}{'source'}})
            {   my $obj = _o($src);
                $obj
                    = $build->up_to_date($src, $obj)
                    ? $obj
                    : sub {
                    print "Compiling $src...\n";
                    return
                        $self->compile(
                          {source       => $src,
                           include_dirs => [
                               $Config{'incpath'},
                               $build->fltk_dir(),
                               $build->fltk_dir($self->notes('headers_path')),
                               $build->fltk_dir(
                                    $self->notes('include_path_compatability')
                               ),
                               $build->fltk_dir(
                                           $self->notes('include_path_images')
                                               . '/zlib/'
                               ),
                               (keys %{$self->notes('include_dirs')})
                           ],
                           cxxflags => [$Config{'ccflags'}, '-MD'],
                           output   => $obj
                          }
                        );
                    }
                    ->();
                if (!$obj) {
                    printf 'Failed to compile %s', $src;
                    exit 0;
                }
                push @obj, $obj;
            }
            my $_lib = _rel($build->fltk_dir('lib/' . _a($lib)));
            $lib
                = $build->up_to_date(\@obj, $_lib)
                ? $_lib
                : $self->archive({output  => $_lib,
                                  objects => \@obj
                                 }
                );
            if (!$lib) {
                printf 'Failed to create %s library', $lib;
                exit 0;
            }
            push @{$self->notes('libs')}, _abs($lib);
        }
        if (!chdir $build->fltk_dir()) {
            print 'Failed to cd to ' . $self->fltk_dir() . ' to return home';
            exit 0;
        }
        return scalar @{$self->notes('libs')};
    }

    # Module::Build actions
    sub ACTION_fetch_fltk {
        my ($self, %args) = @_;
        $args{'to'} = _abs(
            defined $args{'to'} ? $args{'to'} : $self->notes('snapshot_dir'));
        $args{'ext'}    ||= [qw[gz bz2]];
        $args{'scheme'} ||= [qw[http ftp]];
        {
            my ($file) = grep {-f} map {
                _abs(sprintf '%s/fltk-%s-r%d.tar.%s',
                     $args{'to'}, $self->notes('branch'),
                     $self->notes('svn'), $_)
            } @{$args{'ext'}};
            if (defined $file) {
                $self->notes('snapshot_path' => $file);
                $self->notes('snapshot_dir'  => $args{'to'});
                return $self->depends_on('verify_snapshot');
            }
        }
        require File::Fetch;
        $File::Fetch::TIMEOUT = $File::Fetch::TIMEOUT = 45;    # Be quick
        printf "Fetching SVN snapshot %d... ", $self->notes('svn');
        my ($schemes, $exts, %mirrors)
            = ($args{'scheme'}, $args{'ext'}, _snapshot_mirrors());
        my ($attempt, $total)
            = (0, scalar(@$schemes) * scalar(@$exts) * scalar(keys %mirrors));
        my $mirrors = [keys %mirrors];
        {                                                      # F-Y shuffle
            my $i = @$mirrors;
            while (--$i) {
                my $j = int rand($i + 1);
                @$mirrors[$i, $j] = @$mirrors[$j, $i];
            }
        }
        my ($dir, $archive, $extention);
    MIRROR: for my $mirror (@$mirrors) {
        EXT: for my $ext (@$exts) {
            SCHEME: for my $scheme (@$schemes) {
                    printf "\n[%d/%d] Trying %s mirror based in %s... ",
                        ++$attempt, $total, uc $scheme, $mirror;
                    my $ff =
                        File::Fetch->new(
                              uri => sprintf
                                  '%s://%s/fltk/snapshots/fltk-%s-r%d.tar.%s',
                              $scheme, $mirrors{$mirror},
                              $self->notes('branch'),
                              $self->notes('svn'), $ext
                        );
                    $archive = $ff->fetch(to => $args{'to'});
                    if ($archive and -f $archive) {
                        $self->notes('snapshot_mirror_uri'      => $ff->uri);
                        $self->notes('snapshot_mirror_location' => $mirror);
                        $archive = _abs(sprintf '%s/fltk-%s-r%d.tar.%s',
                                        $args{'to'}, $self->notes('branch'),
                                        $self->notes('svn'), $ext);
                        $extention = $ext;
                        $dir       = $args{'to'};
                        last MIRROR;
                    }
                }
            }
        }
        if (!$archive) {    # bad news
            my (@urls, $i);
            for my $ext (@$exts) {
                for my $mirror (sort values %mirrors) {
                    for my $scheme (@$schemes) {
                        push @urls,
                            sprintf
                            '[%d] %s://%s/fltk/snapshots/fltk-%s-r%d.tar.%s',
                            ++$i, $scheme, $mirror,
                            $self->notes('branch'),
                            $self->notes('svn'), $ext;
                    }
                }
            }
            my $urls = join "\n", @urls;
            $self->_error(
                    {stage => 'fltk source download',
                     fatal => 1,
                     message =>
                         sprintf
                         <<'END', _abs($self->notes('snapshot_dir')), $urls});
Okay, we just failed at life.

If you want, you may manually download a snapshot and place it in
    %s

Please, use one of the following mirrors:
%s

Exiting...
END
        }
        print "done.\n";
        $self->notes('snapshot_dir'  => $args{'to'});
        $self->notes('snapshot_path' => $archive);
        $self->notes('snapshot_dir'  => $dir);       # Unused but good to know
             #$self->add_to_cleanup($dir);
        return $self->depends_on('verify_snapshot');
    }

    sub _snapshot_mirrors {
        return (
            'California, USA' => 'ftp.easysw.com/pub',
            'New Jersey, USA' => 'ftp2.easysw.com/pub',
            'Espoo, Finland' => 'ftp.funet.fi/pub/mirrors/ftp.easysw.com/pub',
            'Braunschweig, Germany' =>
                'ftp.rz.tu-bs.de/pub/mirror/ftp.easysw.com/ftp/pub'
        );
    }

    sub ACTION_verify_snapshot {
        my ($self) = @_;
        require Digest::MD5;
        print 'Checking MD5 hash of archive... ';
        my $archive = $self->notes('snapshot_path');
        my ($ext) = $archive =~ m[([^\.]+)$];
        my $FH;
        if (!open($FH, '<', $archive)) {
            $self->_error(
                 {stage   => 'fltk source validation',
                  fatal   => 1,
                  message => "Can't open '$archive' to check MD5 checksum: $!"
                 }
            );    # XXX - Should I delete the archive and retry?
        }
        binmode($FH);
        unshift @INC, _abs(_path($self->base_dir, 'lib'));
        if (eval 'require ' . $self->module_name) {
            my $md5 = $self->module_name->_md5;
            if (Digest::MD5->new->addfile($FH)->hexdigest eq $md5->{$ext}) {
                print "MD5 checksum is okay\n";
                return 1;
            }
        }
        else {
            print "Cannot find checksum. Hope this works out...\n";
            return 1;
        }
        shift @INC;
        close $FH;
        if ($self->notes('bad_fetch_retry')->{'count'}++ > 10) {
            $self->_error(
                {stage => 'fltk source validation',
                 fatal => 1,
                 message =>
                     'Found/downloaded archive failed to match MD5 checksum... Giving up.'
                }
            );
        }
        $self->_error(
            {stage => 'fltk source validation',
             fatal => 0,
             message =>
                 'Found/downloaded archive failed to match MD5 checksum... Retrying.'
            }
        );
        $self->dispatch('fetch_fltk');
    }

    sub ACTION_extract_fltk {
        my ($self, %args) = @_;
        $self->depends_on('fetch_fltk');
        $args{'from'} ||= $self->notes('snapshot_path');
        $args{'to'}   ||= _abs($self->notes('extract_dir'));
        unshift @INC, _abs(_path($self->base_dir, 'lib'));
        my $_extracted;
        if (eval 'require ' . $self->module_name) {
            my $unique_file = $self->module_name->_unique_file;
            $_extracted = -f _abs($args{'to'} . sprintf '/fltk-%s-r%d/%s',
                                  $self->notes('branch'),
                                  $self->notes('svn'),
                                  $unique_file
            ) ? 1 : 0;
        }
        elsif (-d _abs($args{'to'} . sprintf '/fltk-%s-r%d',
                       $self->notes('branch'),
                       $self->notes('svn')
               )
            )
        {   $self->notes('extract' => $args{'to'});
            $_extracted = 1;
            last;
            return 1;    # XXX - what should we do?!?
            require File::Path;
            printf "Removing existing directory...\n", $args{'to'};
            File::Path::remove_tree(_abs($args{'to'} . sprintf '/fltk-%s-r%d',
                                         $self->notes('branch'),
                                         $self->notes('svn')
                                    )
            );
        }
        if (!$_extracted) {
            require Archive::Extract;
            my $ae = Archive::Extract->new(archive => $args{'from'});
            printf 'Extracting %s to %s... ', _rel($args{'from'}),
                _rel($args{'to'});
            if (!$ae->extract(to => $args{'to'})) {
                $self->_error({stage   => 'fltk source extraction',
                               fatal   => 1,
                               message => $ae->error
                              }
                );
            }
            $self->add_to_cleanup($ae->extract_path);
            print "done.\n";
        }
        $self->notes('extract'       => $args{'to'});
        $self->notes('snapshot_path' => $args{'from'});
        return 1;
    }

    sub ACTION_configure {
        my ($self) = @_;
        $self->depends_on('extract_fltk');

        #if (   !$self->notes('define')
        #    || !-f $self->fltk_dir('config.h'))
        {
            print "Gathering configuration data...\n";
            $self->configure();
            $self->notes(timestamp_configure => time);
        }
        return 1;
    }

    sub ACTION_write_config_h {
        my ($self) = @_;

        #return 1
        #    if -f $self->notes('config_yml')
        #        && -s $self->notes('config_yml');
        $self->depends_on('configure');
        if (!chdir $self->fltk_dir()) {
            print 'Failed to cd to '
                . $self->fltk_dir()
                . ' to find config.h';
            exit 0;
        }
        if (   (!-f 'config.h')
            || (!$self->notes('timestamp_config_h'))
            || ($self->notes('timestamp_configure')
                > $self->notes('timestamp_config_h'))
            )
        {   {
                print 'Creating config.h... ';
                if (!chdir $self->fltk_dir()) {
                    print 'Failed to cd to '
                        . $self->fltk_dir()
                        . ' to write config.h';
                    exit 0;
                }
                my $config = '';
                my %config = %{$self->notes('define')};
                for my $key (
                    sort {
                        $config{$a} && $config{$a} =~ m[^HAVE_]
                            ? ($b cmp $a)
                            : ($a cmp $b)
                    } keys %config
                    )
                {   $config .=
                        sprintf((defined $config{$key}
                                 ? '#define %-25s %s'
                                 : '#undef  %-35s'
                                )
                                . "\n",
                                $key,
                                $config{$key}
                        );
                }
                $config .= "\n";
                open(my $CONFIG_H, '>', 'config.h')
                    || Carp::confess 'Failed to open config.h ';
                syswrite($CONFIG_H, $config) == length($config)
                    || Carp::confess 'Failed to write config.h';
                close $CONFIG_H;
                if (!chdir $self->base_dir()) {
                    print 'Failed to cd to base directory';
                    exit 0;
                }
                $self->notes(timestamp_config_h => time);
                print "okay\n";
            }
        }
        if (!chdir $self->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        return 1;
    }

    sub ACTION_write_config_yml {
        my ($self) = @_;
        $self->depends_on('configure');
        require Module::Build::YAML;
        printf 'Updating %s config... ', $self->module_name;
        my $me        = _abs($self->notes('config_yml'));
        my $mode_orig = 0644;
        if (!-d _dir($me)) {
            require File::Path;
            File::Path::make_path(_dir($me), {verbose => 1});
        }
        elsif (-d $me) {
            $mode_orig = (stat $me)[2] & 07777;
            chmod($mode_orig | 0222, $me);    # Make it writeable
        }
        open(my ($YML), '>', $me)
            || $self->_error({stage   => 'config.yml creation',
                              fatal   => 1,
                              message => sprintf 'Failed to open %s: %s',
                              $me, $!
                             }
            );
        syswrite($YML, Module::Build::YAML::Dump(\%{$self->notes()}))
            || $self->_error(
                         {stage   => 'config.yml creation',
                          fatal   => 1,
                          message => sprintf 'Failed to write data to %s: %s',
                          $me, $!
                         }
            );
        chmod($mode_orig, $me)
            || $self->_error(
                   {stage   => 'config.yml creation',
                    fatal   => 0,
                    message => sprintf 'Cannot restore permissions on %s: %s',
                    $me, $!
                   }
            );
        print "okay\n";
    }

    sub ACTION_clear_config {
        my ($self) = @_;
        my $me = $self->notes('config_yml');
        return 1 if !-f $me;
        printf 'Cleaning %s config... ', $self->module_name();
        my $mode_orig = (stat $me)[2] & 07777;
        chmod($mode_orig | 0222, $me);    # Make it writeable
        unlink $me;
        print "okay\n";
    }

    sub ACTION_build_fltk {
        my ($self) = @_;
        $self->depends_on('write_config_h');
        $self->depends_on('write_config_yml');
        if (!chdir $self->fltk_dir()) {
            printf 'Failed to cd to %s to locate libs libs',
                $self->fltk_dir();
            exit 0;
        }
        my @lib = $self->build_fltk($self);
        if (!chdir $self->base_dir()) {
            printf 'Failed to return to %s to copy libs', $self->base_dir();
            exit 0;
        }
        if (!chdir _path($self->fltk_dir() . '/lib')) {
            printf 'Failed to cd to %s to copy libs', $self->fltk_dir();
            exit 0;
        }
        for my $lib (@{$self->notes('libs')}) {
            $self->copy_if_modified(
                            from   => $lib,
                            to_dir => _path($self->base_dir(), qw[share libs])
            );
        }
        if (!chdir $self->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        return 1;
    }

    sub ACTION_code {
        my ($self) = @_;
        $self->depends_on(qw[build_fltk copy_headers]);
        return $self->SUPER::ACTION_code;
    }

    sub _error {
        my ($self, $error) = @_;
        $error->{'fatal'} = defined $error->{'fatal'} ? $error->{'fatal'} : 0;
        my $msg = $error->{'message'};
        $msg =~ s|(.+)|  $1|gm;
        printf "\nWARNING: %s error enountered during %s:\n%s\n",
            ($error->{'fatal'} ? ('*** Fatal') : 'Non-fatal'),
            $error->{'stage'}, $msg, '-- ' x 10;
        if ($error->{'fatal'}) {
            printf STDOUT ('*** ' x 15) . "\n"
                . 'error was encountered during the build process . '
                . "Please correct it and run Build.PL again.\nExiting...",
                exit 0;
        }
    }

    sub ACTION_clean {
        my $self = shift;
        $self->dispatch('clear_config');
        $self->SUPER::ACTION_clean(@_);
        $self->notes(errors => []);    # Reset fatal and non-fatal errors
    }
    {

        # Ganked from Devel::CheckLib
        sub assert_lib {
            my ($self, $args) = @_;
            my (@libs, @libpaths, @headers, @incpaths);

            # FIXME: these four just SCREAM "refactor" at me
            @libs = (
                ref($args->{' lib '})
                ? @{$args->{
                        ' lib
                '
                        }
                    }
                : $args->{' lib '}
            ) if $args->{' lib '};
            @libpaths = (ref($args->{' libpath '})
                         ? @{$args->{' libpath '}}
                         : $args->{' libpath '}
            ) if $args->{' libpath '};
            @headers = (ref($args->{' header '})
                        ? @{$args->{' header '}}
                        : $args->{' header '}
            ) if $args->{' header '};
            @incpaths = (ref($args->{' incpath '})
                         ? @{$args->{' incpath '}}
                         : $args->{' incpath '}
            ) if $args->{' incpath '};
            my @missing;

            # first figure out which headers we can' t find ...
            for my $header (@headers) {
                my $exe =
                    $self->build_exe(
                    {code =>
                         "#include <$header>\nint main(void) { return 0; }\n",
                     include_dirs => \@incpaths,
                     lib_dirs     => \@libpaths
                    }
                    );
                if   (defined $exe && -x $exe) { unlink $exe }
                else                           { push @missing, $header }
            }

            # now do each library in turn with no headers
            for my $lib (@libs) {
                my $exe =
                    $self->build_exe(
                                    {code => "int main(void) { return 0; }\n",
                                     include_dirs       => \@incpaths,
                                     lib_dirs           => \@libpaths,
                                     extra_linker_flags => "-l$lib"
                                    }
                    );
                if   (defined $exe && -x $exe) { unlink $exe }
                else                           { push @missing, $lib }
            }
            my $miss_string = join(q{, }, map {qq{'$_'}} @missing);
            if (@missing) {
                warn "Can't link/include $miss_string\n";
                return 0;
            }
            return 1;
        }

        sub find_lib {
            my ($self, $find, $dir) = @_;
            printf 'Looking for lib%s... ', $find;
            no warnings 'File::Find';
            $find =~ s[([\+\*\.])][\\$1]g;
            $dir ||= $Config{'libpth'};
            $dir = _path($dir);
            my $lib;
            find(
                sub {
                    $lib = _path(_abs($File::Find::dir))
                        if $_ =~ qr[lib$find$Config{'_a'}];
                },
                split ' ',
                $dir
            ) if $dir;
            printf "%s\n", defined $lib ? 'found ' . $lib : 'missing';
            return $lib;
        }

        sub find_h {
            my ($self, $file, $dir) = @_;
            printf 'Looking for %s... ', $file;
            no warnings 'File::Find';
            $dir ||= $Config{'incpath'} . ' ' . $Config{'usrinc'};
            $dir  = _path($dir);
            $file = _path($file);
            my $h;
            find(
                {wanted => sub {
                     return if !-d $_;
                     $h = _path(_abs($_))
                         if -f _path($_, $file);
                 },
                 no_chdir => 1
                },
                split ' ',
                $dir
            ) if $dir;
            if (defined $h) {
                printf "found %s\n", $h;
                $self->notes('include_dirs')->{$h}++;
                return $h;
            }
            print "missing\n";
            return ();
        }
    }
    1;
}

=pod

=head1 FLTK 1.3.x Configuration Options

=head2 C<BORDER_WIDTH>

Thickness of C<FL_UP_BOX> and C<FL_DOWN_BOX>.  Current C<1,2,> and C<3> are
supported.

  3 is the historic FLTK look.
  2 is the default and looks (nothing) like Microsoft Windows, KDE, and Qt.
  1 is a plausible future evolution...

Note that this may be simulated at runtime by redefining the boxtypes using
C<Fl::set_boxtype()>.

=head1 FLTK 2.0.x Configuration Options

TODO

=cut
