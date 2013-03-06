#!/usr/bin/perl -w
#
# Author: David Yan (davidyan at-sign gmail.com)
# This program is distributed under the terms of the GPL License Version 2.
#

use strict;
use Getopt::Std;
use Encode;
use Encode::CN;
use Encode::TW;
use Encode::JP;
use Encode::KR;
use Encode::HanExtra;
use Encode::CNMap;
use Encode::Guess;
use MP3::Tag;
use utf8;

my $is_dry_run;
my $is_verbose;

sub usage {
   my $msg =<<END;
mp3_tag_iconv [-f <from encoding>] [-t <to encoding>] [-n] [-d] [-v] <file> ...
  Options: f - original encoding (default: Guess)
           t - target encoding (default: utf-8, specify utf-8-zhcn or utf-8-zhtw for conversion to Simplified or Traditional Chinese)
           n - dry run
           d - specified files are treated as directories (convert *.mp3 in directory)
           v - verbose
END
   return $msg;
}

sub debug {
   my ($msg) = @_;
   print "$msg\n" if $is_verbose;
}

sub convert_text {
   my ($text, $from_enc, $to_enc) = @_;

   if ($from_enc eq 'Guess') {
       my $enc = guess_encoding($text, qw/gb18030 big5-hkscs utf-8/);
       $from_enc = $enc->name;
   } elsif ($from_enc eq 'gb2312' || $from_enc eq 'gbk') {
       $from_enc = 'gb18030';
   } elsif ($from_enc eq 'big5') {
       $from_enc = 'big5-hkscs';
   } elsif ($from_enc eq 'utf8') {
       $from_enc = 'utf-8';
   }

   if ($to_enc eq 'gb2312' || $to_enc eq 'gbk') {
       $to_enc = 'gb18030';
   } elsif ($to_enc eq 'big5') {
       $to_enc = 'big5-hkscs';
   } elsif ($to_enc eq 'utf8') {
       $to_enc = 'utf-8';
   }

   my $to_zhtw;
   my $to_zhcn;

   debug("CONVERT $from_enc => $to_enc");

   if (($from_enc eq 'gb18030' || $from_enc eq 'utf-8') &&
       ($to_enc eq 'big5-hkscs' || $to_enc eq 'utf-8-zhtw')) {
       $to_zhtw = 1;
       if ($to_enc eq 'utf-8-zhtw') {
           $to_enc = 'utf-8';
       }
   } elsif (($from_enc eq 'big5-hkscs' || $from_enc eq 'utf-8') &&
            ($to_enc eq 'gb18030' || $to_enc eq 'utf-8-zhcn')) {
       $to_zhcn = 1;
       if ($to_enc eq 'utf-8-zhcn') {
           $to_enc = 'utf-8';
       }
   }

   $text = decode($from_enc, $text) unless utf8::is_utf8($text);

   if ($to_zhtw) {
       $text = utf8_to_tradutf8($text);
   } elsif ($to_zhcn) {
       $text = utf8_to_simputf8($text);
   }

   if ($to_enc ne 'utf-8') {
       $text = encode($to_enc, $text);
   }
   return $text;
}

sub process {
   my ($file, $from_enc, $to_enc) = @_;
   my $mp3 = MP3::Tag->new($file);
   debug("Processing $file...");
   $mp3->get_tags();
   my $enc_num;

   if ($to_enc =~ /^utf-8/i) {
       $enc_num = 3;
   } elsif ($to_enc =~ /^utf-16be/i) {
       $enc_num = 2;
   } elsif ($to_enc =~ /^utf-16/i) {
       $enc_num = 1;
   } else {
       $enc_num = 0;
   }

   if (exists $mp3->{ID3v2}) {
       my $id3v2 = $mp3->{ID3v2};
       debug("ID3v2 tag exists.");
       my $frames = $id3v2->get_frame_ids('truename');
       foreach my $frame (keys %$frames) {
	   if ($frame ne 'APIC') {
           my $newvalue;
           debug("FRAME - $frame");
           my ($value, $desc) = $id3v2->get_frame($frame,'intact');
           if (ref $value) {
               while(my ($key,$val)=each %$value) {
                   $val = convert_text($val,$from_enc,$to_enc);
                   debug("TBW===> $frame ($key) => $val");
                   $$newvalue{$key} = $val;
               }
           } else {
               $value = convert_text($value, $from_enc, $to_enc);
               debug("TBW===> $frame => $value");
               $value =~ s/^\(C\) // if ($frame eq 'TCOP');
               push(@$newvalue, $value);
           }
           if ($frame eq 'COMM' or $frame eq 'WXXX' or $frame eq 'PRIV' or $frame eq 'TXXX') {
               $id3v2->change_frame($frame, $enc_num, $$newvalue{'Language'}, $$newvalue{'Description'}, $$newvalue{'Text'});
           } else {
               if (ref $newvalue eq 'ARRAY') {
               $id3v2->change_frame($frame, $enc_num, @$newvalue);
               }
           }
           }
       }
       if (!$is_dry_run) {
           debug("Writing ID3v2 tag.");
           $id3v2->write_tag();
	   if (exists $mp3->{ID3v1}) {
	       $mp3->{ID3v1}->remove_tag();
	   }
       }
   } elsif (exists $mp3->{ID3v1}) {
       my $id3v1 = $mp3->{ID3v1};
       debug("ID3v1 exists.");
       my $title = convert_text($id3v1->title, $from_enc, $to_enc);
       my $artist = convert_text($id3v1->artist, $from_enc, $to_enc);
       my $album = convert_text($id3v1->album, $from_enc, $to_enc);
       my $genre = convert_text($id3v1->genre, $from_enc, $to_enc);
       my $year = $id3v1->year;
       my $track = $id3v1->track;
       my $comment = convert_text($id3v1->comment, $from_enc, $to_enc);
       debug("TBW===> Title: ".$title);
       debug("TBW===> Artist: ".$artist);
       debug("TBW===> Album: ".$album);
       debug("TBW===> Genre: ".$genre);
       debug("TBW===> Comment: ".$comment);
       
       if (!$is_dry_run) {
	   my $id3v2 = $mp3->new_tag("ID3v2");
	   $id3v2->add_frame("TIT2", $enc_num, $title);
	   $id3v2->add_frame("TPE1", $enc_num, $artist);
	   $id3v2->add_frame("TALB", $enc_num, $album);
	   $id3v2->add_frame("TCON", $enc_num, $genre);
	   $id3v2->add_frame("TYER", $enc_num, $year);
	   $id3v2->add_frame("TRCK", $enc_num, $track);
	   $id3v2->add_frame("COMM", $enc_num, "ENG", "", $comment);
           debug("Writing ID3v2 tag.");
           $id3v2->write_tag();
	   $id3v1->remove_tag();
       }
   }


   $mp3->close();
}

sub main {
   binmode STDOUT, ":utf8";
   my %options=();
   getopts("f:t:dnv",\%options) or die usage();

   my $from_enc = defined($options{'f'}) ? $options{'f'} : "Guess";
   my $to_enc = defined($options{'t'}) ? $options{'t'} : "utf-8";
   my $is_dir = defined($options{'d'});
   $is_dry_run = defined($options{'n'});
   $is_verbose = defined($options{'v'});

   my @files;

   if (!@ARGV) {
       die usage();
   }
   if ($is_dir) {
       foreach my $dir (@ARGV) {
           opendir(DIR, $dir) || die "can't opendir $dir: $!";
           push(@files, grep { /\.mp3$/i && -f "$dir/$_" } readdir(DIR));
           closedir DIR;
       }
   } else {
       @files = @ARGV;
   }

   foreach my $file (@files) {
       process($file, $from_enc, $to_enc);
       debug("\n");
   }

   return 0;
}

exit main();
