package inc::MBX::Alien::FLTK::Platform::Windows::MSVC;
{ # See also http://translate.googleusercontent.com/translate_c?hl=en&sl=zh-CN&u=http://crasyrobot.blogbus.com/&prev=/search%3Fq%3Dcannot%2Bconvert%2Bparameter%2B1%2Bfrom%2B%2527struct%2BPrimaryAssociation%2B*%2527%2Bto%2B%2527const%2Bclass%2Bfltk::AssociationType%2B*%2527%26num%3D100%26hl%3Den%26safe%3Doff&rurl=translate.google.com&twu=1&usg=ALkJrhilaCZnBQw-pjQ76w-Q2Vd3B8qaxA
    use strict;
    use warnings;
    use Carp qw[];
    use Config qw[%Config];
    use lib '../../../../../../';
    use inc::MBX::Alien::FLTK::Utility
        qw[run _cwd _path _o _a _rel _abs can_run];
    use inc::MBX::Alien::FLTK;
    use base 'inc::MBX::Alien::FLTK::Platform::Windows';
    $|++;

    sub archive {
        my ($self, $args) = @_;
        my $arch = $args->{'output'};
        my @cmd = ('link.exe -lib ',
                   (map { _rel($_) } @{$args->{'objects'}}),
                   sprintf ' /nologo /out:"%s"', $arch
        );
        print STDERR "@cmd\n" if !$self->quiet;
        return run(@cmd) ? $arch : ();
    }

    sub configure {
        my $self = shift;
        $self->notes('_a'       => $Config{'_a'});
        $self->notes('ldflags'  => '');
        $self->notes('cxxflags' => '');
        $self->notes('cflags'   => '');
        $self->notes('GL'       => '');
        $self->notes('define'   => {});
        $self->notes('image_flags' => ($self->notes('branch') eq '1.3.x'
                                       ? ' -lfltk_images '
                                       : ' -lfltk2_images '
                     )
        );
        $self->notes('include_dirs'  => {});
        $self->notes('library_paths' => {});

        # Not all of FLTK is compatible/applicable with MSVC...
        my @remove = qw[WidgetAssociation.cxx];

   # and some asshole decided to put a load of #warning pragma in the codebase
        my $libs = $self->notes('libs_source');
        for my $lib (sort { lc $a cmp lc $b } keys %$libs) {
            next if $libs->{$lib}{'disabled'};
            my $cwd = _abs(_cwd());
            if (!chdir _path($self->fltk_dir(), $libs->{$lib}{'directory'})) {
                printf 'Cannot chdir to %s to build %s: %s',
                    _path($self->fltk_dir(), $libs->{$lib}{'directory'}),
                    $lib, $!;
                exit 0;
            }
            for my $src (sort { lc $a cmp lc $b } @{$libs->{$lib}{'source'}})
            {

#if (grep { $_ eq $src } @remove ) {
#    printf "Removing %s from build...\n",$src;
#    @{$libs->{$lib}{'source'}} = grep { $_ ne $src } @{$libs->{$lib}{'source'}};
#    next;
#}
                open(my ($fh), '+<', $src) || do {
                    printf
                        "Failed to open %s to check for #warning pragmas: %s\n",
                        $src, $!;
                    next;
                };
                sysread($fh, my ($data), -s $fh) == -s $fh || do {
                    printf
                        "Failed to slurp %s to check for #warning pragmas: %s\n",
                        $src, $!;
                    next;
                };
                if ($data =~ s[^(#\s*warning .+)$][//$1]mg) {
                    printf
                        'Removing incompatible #warning pragmas from %s... ',
                        $src;
                    seek($fh, 0, 0) || do {
                        printf
                            "Failed to seek in %s to correct #warning pragmas: %s\n",
                            $src, $!;
                        next;
                    };
                    syswrite($fh, $data) == length($data)
                        || do {
                        printf
                            "Failed to write %s to correct #warning pragmas: %s\n",
                            $src, $!;
                        next;
                        };
                    print "done\n";
                }

#do { printf "Failed to open %s to check for #warning pragmas: %s\n", $src, $!; next };
                close $fh;
            }
        }
        $self->notes(
            'define' => {

                #WINVER          => 0x0500,
                WORDS_BIGENDIAN => 0,
                U16             => 'unsigned short',
                U32             => 'unsigned',
                U64             => undef,
                USE_COLORMAP    => 1,
                USE_XFT         => 0,
                USE_CAIRO        => 0,    # defined in msvc project settings
                USE_CLIPOUT      => 0,
                HAVE_OVERLAY     => 0,
                USE_OVERLAY      => 0,
                USE_XINERAMA     => 0,
                USE_MULTIMONITOR => 1,
                USE_STOCK_BRUSH  => 1,
                USE_XIM          => 1,
                HAVE_ICONV       => 0,
                HAVE_GL          => 1,
                HAVE_GL_GLU_H    => 1,
                HAVE_GL_OVERLAY      => 'HAVE_OVERLAY',
                USE_GL_OVERLAY       => 0,
                HAVE_DIRENT_H        => 1,
                HAVE_STRING_H        => 1,
                HAVE_STRINGS_H       => 1,
                HAVE_VSNPRINTF       => 1,
                HAVE_SNPRINTF        => 1,
                HAVE_STRCASECMP      => 1,
                HAVE_STRDUP          => 1,
                HAVE_STRNCASECMP     => 1,
                USE_POLL             => 0,
                HAVE_LIBPNG          => 1,
                HAVE_LIBZ            => 1,
                HAVE_LIBJPEG         => 1,
                HAVE_LOCAL_PNG_H     => 1,
                HAVE_LOCAL_JPEG_H    => 1,
                HAVE_PTHREAD         => 1,
                HAVE_PTHREAD_H       => 1,
                HAVE_DLOPEN          => 0,
                BOXX_OVERLAY_BUGS    => 0,
                SGI320_BUG           => 0,
                CLICK_MOVES_FOCUS    => 0,
                IGNORE_NUMLOCK       => 1,
                USE_PROGRESSIVE_DRAW => 1
            }
        );
        for my $lib (keys %{$self->notes('libs_source')}) {
            $self->notes('libs_source')->{$lib}{'disabled'}++
                if $lib =~ m[glut$]i;
        }
        $self->notes(ldflags => $self->notes('ldflags')
            . ' ws2_32.lib kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib msimg32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib '
            . ' /nologo /incremental:no'
            . ' /machine:I386'
            . ' /nodefaultlib:"libcd" /nodefaultlib:"libcmt"');
        for my $type (qw[cflags cxxflags]) {
            $self->notes($type => '/nologo /MD /Ob2 /W3 /GX /Os'
                . ' /D "_WIN32" /D "WINVER=0x0500" /D "WIN32" '
                . $self->notes($type)
                . ' /D "NDEBUG" /D "WIN32" /D "_WINDOWS" /D "WIN32_LEAN_AND_MEAN"'
                . ' /D "VC_EXTRA_LEAN" /D "WIN32_EXTRA_LEAN" /D "_MSC_DLL" '
            );
        }
        $self->notes('define')->{'_WIN32'} = 1;
        $self->notes('define')->{'WIN32'}  = 1;
        return 1;
    }
    1;
}

=pod

=head1 Author

Sanko Robinson <sanko@cpan.org> - http://sankorobinson.com/

CPAN ID: SANKO

=head1 License and Legal

Copyright (C) 2009 by Sanko Robinson E<lt>sanko@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it under
the terms of The Artistic License 2.0. See the F<LICENSE> file included with
this distribution or http://www.perlfoundation.org/artistic_license_2_0.  For
clarification, see http://www.perlfoundation.org/artistic_2_0_notes.

When separated from the distribution, all POD documentation is covered by the
Creative Commons Attribution-Share Alike 3.0 License. See
http://creativecommons.org/licenses/by-sa/3.0/us/legalcode.  For
clarification, see http://creativecommons.org/licenses/by-sa/3.0/us/.

=for git $Id$

=cut
