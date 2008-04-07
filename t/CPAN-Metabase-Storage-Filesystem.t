# Copyright (c) 2008 by Ricardo Signes. All rights reserved.
# Licensed under terms of Perl itself (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License was distributed with this file or you may obtain a 
# copy of the License from http://dev.perl.org/licenses/

use strict;
use warnings;

use Test::More;
use Test::Exception;
use File::Temp ();

use lib 't/lib';
use CPAN::Metabase::TestFact;

plan tests => 9;

require_ok( 'CPAN::Metabase::Storage::Filesystem' );

# die on missing or non-existing directory
my $re_bad_root_dir = qr/\QAttribute (root_dir)\E/;
throws_ok { CPAN::Metabase::Storage::Filesystem->new() } $re_bad_root_dir;
throws_ok { 
    CPAN::Metabase::Storage::Filesystem->new(root_dir => 'doesntexist') 
} $re_bad_root_dir;

# store into a temp directory
#my $temp_root = File::Temp->newdir() or die;
my $temp_root = 'eg/store';

my $storage;
lives_ok { 
    $storage = CPAN::Metabase::Storage::Filesystem->new(root_dir => "$temp_root");
} "created store at '$temp_root'";

my $fact = CPAN::Metabase::TestFact->new({ odor => 'sweet' });

isa_ok( $fact, 'CPAN::Metabase::TestFact' );

ok( my $guid = $storage->store( $fact ), "stored a fact" );

ok( my $copy = $storage->extract( "CPAN::Metabase::TestFact", $guid ),
    "got a fact from storage"
);

for my $p ( qw/odor type/ ) {
    is( $copy->$p, $fact->$p, "second object has same $p" )
}


