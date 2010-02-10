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
        qw[_o _a _path _realpath _dir _file _rel _abs _exe _cwd can_run run];
    use lib '.';

    sub fltk_dir {
        my ($self, $extra) = @_;
        $self->depends_on('extract_fltk');
        return (_path($self->base_dir,
                      $self->notes('extract'),
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
        return run(@cmd) ? $arch : ();
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
        return $obj ? $obj : ();
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
        return $exe ? $exe : ();
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
        $self->notes('_a'       => $Config{'_a'});
        $self->notes('ldflags'  => '');
        $self->notes('cxxflags' => '');
        $self->notes('GL'       => '');
        $self->notes('define'   => {});
        $self->notes(
            'image_flags' => (

                #"-lpng -lfltk2_images -ljpeg -lz"
                $self->notes('branch') eq '1.3.x'
                ? ' -lfltk_images '
                : ' -lfltk2_images '
            )
        );
        $self->notes('include_dirs'  => {});
        $self->notes('library_paths' => {});
        {
            print 'Locating library archiver... ';
            my $ar = can_run('ar');
            if (!$ar) {
                print "Could not find the library archiver, aborting.\n";
                exit 0;
            }
            $ar .= ' cr' . (can_run('ranlib') ? 's' : '');
            $self->notes(AR => $ar);
            print "$ar\n";
        }
        {
            my %sizeof;
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

                $sizeof{$type} = $exe ? `$exe` : 0;
                print "okay\n";
            }

            #
            if ($sizeof{'short'} == 2) {
                $self->notes('define')->{'U16'} = 'unsigned short';
            }
            if ($sizeof{'int'} == 4) {
                $self->notes('define')->{'U32'} = 'unsigned';
            }
            else {
                $self->notes('define')->{'U32'} = 'unsigned long';
            }
            if ($sizeof{'int'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned';
            }
            elsif ($sizeof{'long'} == 8) {
                $self->notes('define')->{'U64'} = 'unsigned long';
            }
        }
        {
            print
                'Checking whether the compiler recognizes bool as a built-in type... ';
            my $exe = $self->build_exe({code => <<"" });
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
                $self->notes(  'cxxflags' => $self->notes('cxxflags')
                             . ' -Dbool=char -Dfalse=0 -Dtrue=1 ');
            }
        }
        if (0 && can_run('sh')) {
            my $cwd = cwd;
            warn _abs cwd;
            if (chdir(_abs $self->fltk_dir())
                && run('sh', './configure'))
            {                    #use Data::Dump;
                my @defines = qw[FLTK_DATADIR FLTK_DOCDIR BORDER_WIDTH
                    USE_X11 USE_QUARTZ __APPLE_QUARTZ__ __APPLE_QD__
                    USE_COLORMAP USE_X11_MULTITHREADING USE_XFT USE_XCURSOR
                    USE_CAIRO USE_CLIPOUT USE_XSHM HAVE_XDBE USE_XDBE HAVE_OVERLAY
                    USE_OVERLAY USE_XINERAMA USE_MULTIMONITOR USE_STOCK_BRUSH
                    USE_XIM HAVE_ICONV HAVE_GL HAVE_GL_GLU_H HAVE_GL_OVERLAY
                    USE_GL_OVERLAY USE_GLEW HAVE_GLXGETPROCADDRESSARB
                    HAVE_DIRENT_H HAVE_STRING_H HAVE_SYS_NDIR_H HAVE_SYS_DIR_H
                    HAVE_NDIR_H HAVE_SCANDIR HAVE_SCANDIR_POSIX HAVE_STRING_H
                    HAVE_STRINGS_H HAVE_VSNPRINTF HAVE_SNPRINTF HAVE_STRCASECMP
                    HAVE_STRDUP HAVE_STRLCAT HAVE_STRLCPY HAVE_STRNCASECMP
                    HAVE_SYS_SELECT_H HAVE_SYS_STDTYPES_H USE_POLL HAVE_LIBPNG
                    HAVE_LIBZ HAVE_LIBJPEG HAVE_LOCAL_PNG_H HAVE_PNG_H
                    HAVE_LIBPNG_PNG_H HAVE_LOCAL_JPEG_H HAVE_PTHREAD
                    HAVE_PTHREAD_H HAVE_EXCEPTIONS HAVE_DLOPEN BOXX_OVERLAY_BUGS
                    SGI320_BUG CLICK_MOVES_FOCUS IGNORE_NUMLOCK
                    USE_PROGRESSIVE_DRAW HAVE_XINERAMA];

                #ddx @defines;
                my $print = '';
                for my $key (@defines) {
                    $print
                        .= '#ifdef ' 
                        . $key . "\n"
                        . '    printf("'
                        . $key
                        . q[ => '%s'\n,", ]
                        . $key . ");\n"
                        . '#endif // #ifdef '
                        . $key . "\n";
                }

                #print $print;
                my $exe =
                    $self->build_exe({include_dirs => [$self->fltk_dir()],
                                      code         => sprintf <<'', $print});
#include <config.h>
#include <stdio.h>
int main ( ) {
printf("{\n");
%s
printf("};\n");
return 0;
}

                if ($exe) {
                    warn $exe;
                    warn -f $exe;
                    warn system($exe);
                    my $eval = `$exe`;
                    warn `$exe`;
                    die $eval;
                    die 'blah';
                }
                return 1;
            }
        }
        {
            $self->notes('define')->{'FLTK_DATADIR'} = '""';    # unused
            $self->notes('define')->{'FLTK_DOCDIR'}  = '""';    # unused
            $self->notes('define')->{'BORDER_WIDTH'} = 2;       # unused
            $self->notes('define')->{'WORDS_BIGENDIAN'}
                = ((unpack('h*', pack('s', 1)) =~ /01/) ? 1 : 0);    # both
            $self->notes('define')->{'USE_COLORMAP'}           = 1;
            $self->notes('define')->{'USE_X11_MULTITHREADING'} = 0;
            $self->notes('define')->{'USE_XFT'}                = 0;
            $self->notes('define')->{'USE_CAIRO'}
                = ($self->notes('branch') eq '2.0.x' ? 0 : undef);
            $self->notes('define')->{'USE_CLIPOUT'}      = 0;
            $self->notes('define')->{'USE_XSHM'}         = 0;
            $self->notes('define')->{'HAVE_XDBE'}        = 0;
            $self->notes('define')->{'USE_XDBE'}         = 'HAVE_XDBE';
            $self->notes('define')->{'HAVE_OVERLAY'}     = 0;
            $self->notes('define')->{'USE_OVERLAY'}      = 0;
            $self->notes('define')->{'USE_XINERAMA'}     = 0;
            $self->notes('define')->{'USE_MULTIMONITOR'} = 1;
            $self->notes('define')->{'USE_STOCK_BRUSH'}  = 1;
            $self->notes('define')->{'USE_XIM'}          = 1;
            $self->notes('define')->{'HAVE_ICONV'}       = 0;
            $self->notes('define')->{'HAVE_GL'}
                = $self->assert_lib({headers => ['GL/gl.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_GL_GLU_H'}
                = $self->assert_lib({headers => ['GL/glu.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_GL_OVERLAY'} = 'HAVE_OVERLAY';
            $self->notes('define')->{'USE_GL_OVERLAY'}  = 0;
            $self->notes('define')->{'USE_GLEW'}        = 0;
            $self->notes('define')->{'HAVE_DIRENT_H'}
                = $self->assert_lib({headers => ['dirent.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_STRING_H'}
                = $self->assert_lib({headers => ['string.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SYS_NDIR_H'}
                = $self->assert_lib({headers => ['sys/ndir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SYS_DIR_H'}
                = $self->assert_lib({headers => ['sys/dir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_NDIR_H'}
                = $self->assert_lib({headers => ['ndir.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_SCANDIR'}       = 1;
            $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = undef;
            $self->notes('define')->{'HAVE_STRING_H'}
                = $self->assert_lib({headers => ['string.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_STRINGS_H'}
                = $self->assert_lib({headers => ['strings.h']}) ? 1 : undef;
            $self->notes('define')->{'HAVE_VSNPRINTF'}   = 1;
            $self->notes('define')->{'HAVE_SNPRINTF'}    = 1;
            $self->notes('define')->{'HAVE_STRCASECMP'}  = undef;
            $self->notes('define')->{'HAVE_STRDUP'}      = undef;
            $self->notes('define')->{'HAVE_STRLCAT'}     = undef;
            $self->notes('define')->{'HAVE_STRLCPY'}     = undef;
            $self->notes('define')->{'HAVE_STRNCASECMP'} = undef;
            $self->notes('define')->{'HAVE_SYS_SELECT_H'}
                = $self->assert_lib({headers => ['sys/select.h']})
                ? 1
                : undef;
            $self->notes('define')->{'HAVE_SYS_STDTYPES_H'}
                = $self->assert_lib({headers => ['sys/stdtypes.h']})
                ? 1
                : undef;
            $self->notes('define')->{'USE_POLL'} = 0;
            {
                my $png_lib;
                if ($self->assert_lib({libs    => ['png'],
                                       headers => ['libpng/png.h'],
                                       code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char png_read_rows ( );
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'} = 1;
                    $png_lib = ' -lpng ';
                }
                elsif ($self->assert_lib({libs    => ['png'],
                                          headers => ['local/png.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char png_read_rows ( );
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'}      = 1;
                    $self->notes('define')->{'HAVE_LOCAL_PNG_H'} = 1;
                    $png_lib .= ' -lpng ';
                }
                elsif ($self->assert_lib({libs    => ['png'],
                                          headers => ['png.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char png_read_rows ( );
int main ( ) { return png_read_rows( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBPNG'} = 1;
                    $png_lib .= ' -lpng ';
                }
                else {
                    $png_lib .= ($self->notes('branch') eq '1.3.x'
                                 ? ' -lfltk_png '
                                 : ' -lfltk2_png '
                    );
                }
                if ($self->assert_lib({libs => ['z'], code => <<''})) {
#ifdef __cplusplus
extern "C"
#endif
char gzopen ();
int main () { return gzopen( ); return 0; }

                    $self->notes('define')->{'HAVE_LIBZ'} = 1;
                    $png_lib .= ' -lz ';
                }
                else {
                    $png_lib .= ($self->notes('branch') eq '1.3.x'
                                 ? ' -lfltk_z '
                                 : ' -lfltk2_z '
                    );
                }
                $self->notes('define')->{'HAVE_PNG_H'} = undef
                    ;  # $self->assert_lib({headers => ['png.h']}) ? 1 : undef
                $self->notes('define')->{'HAVE_LIBPNG_PNG_H'} = undef
                    ; #$self->assert_lib({headers => ['libpng/png.h']}) ? 1 : undef
                      # Add to list
                $self->notes(
                     'image_flags' => $png_lib . $self->notes('image_flags'));
            }
            {
                my $jpeg_lib;
                if ($self->assert_lib({libs    => ['jpeg'],
                                       headers => ['jpeglib.h'],
                                       code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char jpeg_destroy_decompress ( );
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'} = 1;
                    $jpeg_lib = ' -ljpeg ';
                }
                elsif ($self->assert_lib({libs    => ['jpeg'],
                                          headers => ['local/jpeg.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char jpeg_destroy_decompress ( );
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'}      = 1;
                    $self->notes('define')->{'HAVE_LOCAL_JPEG_H'} = 1;
                    $jpeg_lib .= ' -ljpeg ';
                }
                elsif ($self->assert_lib({libs    => ['jpeg'],
                                          headers => ['jpeg.h'],
                                          code    => <<'' })) {
#ifdef __cplusplus
extern "C"
#endif
char jpeg_destroy_decompress ( );
int main ( ) { return jpeg_destroy_decompress( ); return 0;}

                    $self->notes('define')->{'HAVE_LIBJPEG'} = 1;
                    $jpeg_lib .= ' -ljpeg ';
                }
                else {
                    $jpeg_lib .= ($self->notes('branch') eq '1.3.x'
                                  ? ' -lfltk_jpeg '
                                  : ' -lfltk2_jpeg '
                    );
                }
                if ($self->notes('define')->{'HAVE_LIBZ'}) {
                    $self->notes('image_flags' => $self->notes('image_flags')
                                 . ' -lz');

                    # XXX - Disable building qr[fltk2?_z]?
                }
                else {

       #? ' -lfltk_images -lfltk_png -lfltk_z -lfltk_images -lfltk_jpeg '
       #: ' -lfltk2_images -lfltk2_png -lfltk2_z -lfltk2_images -lfltk2_jpeg '
                    $self->notes('image_flags' => $self->notes('image_flags')
                                     . ($self->notes('branch') eq '1.3.x'
                                        ? ' -lfltk_z'
                                        : ' -lfltk2_z'
                                     )
                    );
                }
                $self->notes('define')->{'HAVE_JPEG_H'} = undef
                    ; # $self->assert_lib({headers => ['jpeg.h']}) ? 1 : undef
                $self->notes('define')->{'HAVE_LIBJPEG_JPEG_H'} = undef
                    ; #$self->assert_lib({headers => ['libjpeg/jpeg.h']}) ? 1 : undef
                      # Add to list
                $self->notes(
                    'image_flags' => $jpeg_lib . $self->notes('image_flags'));
            }
            if ($self->assert_lib(
                               {libs => ['pthread'], headers => ['pthread.h']}
                )
                )
            {   $self->notes('define')->{'HAVE_PTHREAD'}
                    = $self->notes('define')->{'HAVE_PTHREAD_H'} = 1;
            }
            $self->notes('define')->{'HAVE_EXCEPTIONS'}      = undef;
            $self->notes('define')->{'HAVE_DLOPEN'}          = 0;
            $self->notes('define')->{'BOXX_OVERLAY_BUGS'}    = 0;
            $self->notes('define')->{'SGI320_BUG'}           = 0;
            $self->notes('define')->{'CLICK_MOVES_FOCUS'}    = 0;
            $self->notes('define')->{'IGNORE_NUMLOCK'}       = 1;
            $self->notes('define')->{'USE_PROGRESSIVE_DRAW'} = 1;
            $self->notes('define')->{'HAVE_XINERAMA'}        = 0;      # 1.3.x
        }
        {    # Both | All platforms | Standard headers/functions
            my @headers = qw[dirent.h sys/ndir.h sys/dir.h ndir.h];
        HEADER: for my $header (@headers) {
                printf 'Checking for %s that defines DIR... ', $header;
                my $exe = $self->assert_lib(
                               {headers => [$header], code => sprintf <<'' });
#include <stdio.h>
#include <sys/types.h>
int main ( ) {
    if ( ( DIR * ) 0 )
        return 0;
    printf( "1" );
    return 0;
}

                my $define = uc 'HAVE_' . $header;
                if ($exe) {
                    print "yes ($header)\n";
                    $define =~ s|[/\.]|_|g;
                    $self->notes('define')->{$define} = 1;

                    #$self->notes('cache')->{'header_dirent'} = $header;
                    last HEADER;
                }
                else {
                    $self->notes('define')->{$define} = undef;
                    print "no\n";    # But we can pretend...
                }
            }

            #
            $self->notes('define')->{'HAVE_LOCAL_PNG_H'}
                = $self->notes('define')->{'HAVE_LIBPNG'} ? undef : 1;

            #$self->notes('image_flags' => $self->notes('image_flags')
            # -lpng -lfltk2_images -ljpeg -lz
            #
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
                print
                    'Checking whether we have the POSIX compatible scandir() prototype... ';
                my $obj = $self->compile({code => <<'' });
#include <dirent.h>
int func (const char *d, dirent ***list, void *sort) {
    int n = scandir(d, list, 0, (int(*)(const dirent **, const dirent **))sort);
}
int main ( ) {
    return 0;
}

                if ($obj ? 1 : 0) {
                    print "yes\n";
                    $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = 1;
                }
                else {
                    print "no\n";
                    $self->notes('define')->{'HAVE_SCANDIR_POSIX'} = undef;
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
int main () {
    return $func ();
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

=pod oldversion

        $self->notes('define'        => {});
        $self->notes('cache'         => {});
        $self->notes('_a'            => $Config{'_a'});
        $self->notes('cxxflags'      => ' ');
        $self->notes('ldflags'       => ' ');
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
                $self->notes('define')->{'HAVE_SCANDIR'} = 1;
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
            $self->assert_lib({headers=>['pthread.h']});
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
            $self->assert_lib({headers=>['string.h']});
            $self->assert_lib({headers=>['strings.h']});
            $self->assert_lib({headers=>['sys/select.h']});
            $self->assert_lib({headers=>['png.h']});
        }
        {
            print "Setting defaults...\n";
            print "    BORDER_WIDTH = 2\n";
            $self->notes('define')->{'BORDER_WIDTH'} = 2;
            print "    USE_COLORMAP = 1\n";
            $self->notes('define')->{'USE_COLORMAP'} = 1;
            print "    HAVE_GL_OVERLAY = HAVE_OVERLAY\n";
            $self->notes('define')->{'HAVE_GL_OVERLAY'} = 'HAVE_OVERLAY';

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
        if (!chdir $self->base_dir()) {
            print 'Failed to cd to base directory';
            exit 0;
        }
        my $libs = $self->notes('libs_source');
        for my $lib (sort { lc $a cmp lc $b } keys %$libs) {
            next if $libs->{$lib}{'disabled'};
            print "Building $lib...\n";
            my $cwd = _abs(_cwd());
            if (!chdir _path($build->fltk_dir(), $libs->{$lib}{'directory'}))
            {   printf 'Cannot chdir to %s to build %s: %s',
                    _path($build->fltk_dir(), $libs->{$lib}{'directory'}),
                    $lib, $!;
                exit 0;
            }
            my @obj;
            my %include_dirs = %{$self->notes('include_dirs')};
            for my $dir (grep { defined $_ } (
                           split(' ', $Config{'incpath'}),
                           $build->fltk_dir(),
                           '..',
                           map { $build->fltk_dir($_) || () } (
                                $self->notes('include_path_compatability'),
                                $self->notes('include_path_images'),
                                $self->notes('include_path_images') . '/zlib/'
                           )
                         )
                )
            {   $include_dirs{_rel(_realpath($dir))}++;
            }

            #use Data::Dump;
            #ddx \%include_dirs;
            #die;
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
                                      include_dirs => [keys %include_dirs],
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
                push @obj, _abs($obj);
            }
            if (!chdir $cwd) {
                printf 'Cannot chdir to %s after building %s: %s', $cwd, $lib,
                    $!;
                exit 0;
            }
            my $_lib = _rel($build->fltk_dir('lib/' . _a($lib)));
            printf 'Archiving %s... ', $lib;
            $_lib
                = $build->up_to_date(\@obj, $_lib)
                ? $_lib
                : $self->archive({output  => _abs($_lib),
                                  objects => \@obj
                                 }
                );
            if (!$_lib) {
                printf 'Failed to create %s library', $lib;
                exit 0;
            }
            push @{$self->notes('libs')}, $_lib;
            print "done\n";
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
        $args{'to'} = (
            defined $args{'to'} ? $args{'to'} : $self->notes('snapshot_dir'));
        $args{'ext'}    ||= [qw[gz bz2]];
        $args{'scheme'} ||= [qw[http ftp]];
        {
            my ($file) = grep {-f} map {
                (sprintf '%s/fltk-%s-r%d.tar.%s',
                 $args{'to'}, $self->notes('branch'),
                 $self->notes('svn'), $_
                    )
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
                        $archive = (sprintf '%s/fltk-%s-r%d.tar.%s',
                                    $args{'to'},
                                    $self->notes('branch'),
                                    $self->notes('svn'),
                                    $ext
                        );
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
                     sprintf <<'END', ($self->notes('snapshot_dir')), $urls});
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
        return 1 if $self->notes('snapshot_okay');
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
        unshift @INC, (_path($self->base_dir, 'lib'));
        if (eval 'require ' . $self->module_name) {
            my $md5 = $self->module_name->_md5;
            if (Digest::MD5->new->addfile($FH)->hexdigest eq $md5->{$ext}) {
                print "MD5 checksum is okay\n";
                $self->notes('snapshot_okay' => 'Valid @ ' . time);
                return 1;
            }
        }
        else {
            print "Cannot find checksum. Hope this works out...\n";
            $self->notes('snapshot_okay' => 'Pray that it is... @' . time);
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
        $args{'to'}   ||= _rel(($self->notes('extract_dir')));
        unshift @INC, (_path($self->base_dir, 'lib'));
        eval 'require ' . $self->module_name;
        my $unique_file = $self->module_name->_unique_file;
        if (-f ($args{'to'} . sprintf '/fltk-%s-r%d/%s',
                $self->notes('branch'),
                $self->notes('svn'),
                $unique_file
            )
            && !$self->notes('timestamp_extracted')
            )
        {   warn sprintf
                "Odd... Found extracted snapshot at %s... (unique file %s located)\n",
                _rel($args{'to'} . sprintf '/fltk-%s-r%d',
                     $self->notes('branch'),
                     $self->notes('svn')),
                _rel($args{'to'} . sprintf '/fltk-%s-r%d/%s',
                     $self->notes('branch'),
                     $self->notes('svn'), $unique_file);
            $self->notes(timestamp_extracted => time);
            $self->notes('extract'           => $args{'to'});
            $self->notes('snapshot_path'     => $args{'from'});
            return 1;
        }
        elsif (-d ($args{'to'} . sprintf '/fltk-%s-r%d',
                   $self->notes('branch'),
                   $self->notes('svn')
               )
               && !$self->notes('timestamp_extracted')
            )
        {   $self->notes('extract' => $args{'to'});
            warn sprintf
                "Strage... found partially extracted snapshot at %s...\n",
                _rel($args{'to'} . sprintf '/fltk-%s-r%d',
                     $self->notes('branch'),
                     $self->notes('svn'));
            require File::Path;
            print 'Removing existing directory... ', $args{'to'};
            File::Path::remove_tree(($args{'to'} . sprintf '/fltk-%s-r%d',
                                     $self->notes('branch'),
                                     $self->notes('svn')
                                    )
            );
            $self->notes('timestamp_extracted' => undef);
            print "done\n";
        }
        if (!$self->notes('timestamp_extracted')) {
            printf 'Extracting snapshot from %s to %s... ',
                _rel($args{'from'}),
                _rel($args{'to'});
            require Archive::Extract;
            my $ae = Archive::Extract->new(archive => $args{'from'});
            if (!$ae->extract(to => $args{'to'})) {
                $self->_error({stage   => 'fltk source extraction',
                               fatal   => 1,
                               message => $ae->error
                              }
                );
            }
            $self->add_to_cleanup($ae->extract_path);
            $self->notes(timestamp_extracted => time);
            $self->notes('extract'           => $args{'to'});
            $self->notes('snapshot_path'     => $args{'from'});
            print "done.\n";
        }
        return 1;
    }

    sub ACTION_configure {
        my ($self) = @_;
        $self->depends_on('extract_fltk');
        if (!$self->notes('timestamp_configure')

            #   || !$self->notes('define')
            #|| !-f $self->fltk_dir('config.h')
            )
        {   print "Gathering configuration data...\n";
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
        my $me        = ($self->notes('config_yml'));
        my $mode_orig = 0644;
        if (!-d _dir($me)) {
            require File::Path;
            $self->add_to_cleanup(File::Path::make_path(_dir($me)));
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

    sub ACTION_reset_config {
        my ($self) = @_;
        return if !$self->notes('timestamp_configure');
        printf 'Cleaning %s config... ', $self->module_name();
        my $yml = $self->notes('config_yml');
        if (-f $yml) {
            my $mode_orig = (stat $yml)[2] & 07777;
            chmod($mode_orig | 0222, $yml);    # Make it writeable
            unlink $yml;
        }
        $self->notes(timestamp_configure => 0);
        $self->notes(timestamp_extracted => 0);
        print "done\n";
    }

    sub ACTION_build_fltk {
        my ($self) = @_;
        $self->depends_on('write_config_h');
        $self->depends_on('write_config_yml');
        my @lib = $self->build_fltk($self);
        if (!chdir $self->base_dir()) {
            printf 'Failed to return to %s to copy libs', $self->base_dir();
            exit 0;
        }
        for my $lib (@{$self->notes('libs')}) {
            $self->copy_if_modified(
                   from => $lib,
                   to => _path($self->base_dir(), qw[share libs], _file($lib))
            );
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
                exit defined $error->{'exit'} ? $error->{'exit'} : 0;
        }
    }

    sub ACTION_clean {
        my $self = shift;
        $self->dispatch('reset_config');
        $self->SUPER::ACTION_clean(@_);
        $self->notes(errors => []);    # Reset fatal and non-fatal errors
    }
    {

        # Ganked from Devel::CheckLib
        sub assert_lib {
            my ($self, $args) = @_;

            # Defaults
            $args->{'code'}         ||= 'int main( ) { return 0; }';
            $args->{'include_dirs'} ||= ();
            $args->{'lib_dirs'}     ||= ();
            $args->{'headers'}      ||= ();
            $args->{'libs'}         ||= ();

            #use Data::Dumper;
            #warn Dumper $args;
            # first figure out which headers we can' t find...
            for my $header (@{$args->{'headers'}}) {
                printf 'Trying to compile with %s... ', $header;
                if ($self->compile(
                            {code => "#include <$header>\n" . $args->{'code'},
                             include_dirs => $args->{'include_dirs'},
                             lib_dirs     => $args->{'lib_dirs'}
                            }
                    )
                    )
                {   print "okay\n";
                    next;
                }
                print "Cannot include $header\n";
                return 0;
            }

            # now do each library in turn with no headers
            for my $lib (@{$args->{'libs'}}) {
                printf 'Trying to link with %s... ', $lib;
                if ($self->test_exe(
                           {code =>
                                join("\n",
                                (map {"#include <$_>"} @{$args->{'headers'}}),
                                $args->{'code'}),
                            include_dirs       => $args->{'include_dirs'},
                            lib_dirs           => $args->{'lib_dirs'},
                            extra_linker_flags => "-l$lib"
                           }
                    )
                    )
                {   print "okay\n";
                    next;
                }
                print "Cannot link $lib ";
                return 0;
            }
            return 1;
        }

        sub find_lib {
            my ($self, $find, $dir) = @_;
            printf 'Looking for lib%s... ', $find;
            require File::Find::Rule;
            $find =~ s[([\+\*\.])][\\$1]g;
            $dir ||= $Config{'libpth'};
            $dir = _path($dir);
            my @files
                = File::Find::Rule->file()
                ->name('lib' . $find . $Config{'_a'})->maxdepth(1)
                ->in(split ' ', $dir);
            printf "%s\n", @files ? 'found ' . (_dir($files[0])) : 'missing';
            return _path((_dir($files[0])));
        }

        sub find_h {
            my ($self, $file, $dir) = @_;
            printf 'Looking for %s... ', $file;
            $dir = join ' ', ($dir || ''), $Config{'incpath'},
                $Config{'usrinc'};
            $dir =~ s|\s+| |g;
            for my $test (split m[\s+]m, $dir) {
                if (-e _path($test . '/' . $file)) {
                    printf "found in %s\n", _path($test);
                    $self->notes('include_dirs')->{_path($test)}++;
                    return _path($test);
                }
            }
            print "missing\n";
            return ();
        }

        sub _find_h {
            my ($self, $file, $dir) = @_;
            printf 'Looking for %s... ', $file;
            require File::Find::Rule;
            $dir ||= $Config{'incpath'} . ' ' . $Config{'usrinc'};
            $dir  = _path($dir);
            $file = _path($file);
            my @files = File::Find::Rule->file()->name($file)->maxdepth(1)
                ->in(split ' ', $dir);
            if (@files) {
                printf "found in %s\n", _dir($files[0]);
                $self->notes('include_dirs')->{_dir($files[0])}++;
                return _dir($files[0]);
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
