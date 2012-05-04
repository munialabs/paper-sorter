#!/usr/bin/perl

# (C)2012 by muniaLabs

use POSIX;
use utf8;

use Digest::MD5 qw(md5 md5_hex md5_base64);
use Unicode::Normalize;
use Term::ANSIColor;
use Term::ANSIColor qw(:constants);


# parameter: base directory for ebooks-directory
$libDir = '/ebooks/papers';


print "\n\n### paper sorter by muniaLabs\n\n";

# make sure that the base directories exists


# depends on OSX or linux...
$md5exe     = '/usr/bin/md5sum';
$md5options = "";


$OCR = "true";

if ( $#ARGV == -1 ) {
    print "Local directory..\n";
    opendir DIR, '.' or die "open failed : $!\n";
    @flist = readdir DIR;
    closedir DIR or die "close failed : $!\n";
}
else {
    print "Specified files..\n";
    @flist = @ARGV;
}

$count = 0;
foreach $filename (@flist) {
    $count++;

    # skip if specified
    if ( uc($filename) lt uc($startstring) ) {
        print RED, "Skipping $filename\n", RESET;
        next;
    }

    # extract extension
    @filenameparts = split( /\./, $filename );
    if ( scalar(@filenameparts) > 0 ) {
        $ext = $filenameparts[ scalar(@filenameparts) - 1 ];
    }
    print "\nNew file: $filename, extension $ext\n";

    # skip rars
    if ( ( $ext eq "rar" ) || ( $ext eq "zip" ) ) {
        print "seems to be a zip/rar, skipping!\n\n";
        next;
    }

    # correct extension if its a PDF
    $filetype = `file "$filename"`;
    print "  File has type: $filetype\n";
    if ( $filetype =~ m/PDF document/ ) {
        print "  " . $filename . " is a PDF, changing extension.\n";
        $ext = "pdf";
    }

    # main loop

    # next try strategies based on filetype
    if ( $filetype =~ m/PDF document/ ) {

        # correct extension first
        $ext = "pdf";

        # we dont work if we have less than 32 pages! no real book!
        $pdfPages = `pdfinfo \"$filename\"  | grep Pages | sed -e 's/[^0-9]//gi'`;
	$pdfPages =~ tr/0-9//cd;

	print RED, "  PDF has $pdfPages pages.\n", RESET;

	# skip books
        if ($pdfPages > 128)
	{
          print RED, "  Too many pages to be classified as a book.\n", RESET;
	  next;
	}

	$newname = determineArticle( $filename, $pdfPages ).".pdf";

        # try first extracting the PDF by pdftotext
        if ( $newname != -1 ) {
            print GREEN, "  matched $newname!\n", RESET;
            renameFile( $filename, $newname );
            next;
        }

        print RED, "  unable to find paper name from PDF file\n", RESET;
        next;
    }
}

die;


sub determineArticle
{
    my $filename = $_[0];
    my $nPages = $_[1];
    my $match    = -1;

    # remove old cache
    `rm /tmp/pdftext.cache`;

    $startPage = 2;
    $startPage = 50 if ($nPages > 100);

    # just convert the first 24 pages, that should be enough.
    print BLUE, "  Extract max. 24 pages from PDF file $filename..\n",
      RESET;
    `pdftotext -f $startPage -l 24 -q "$filename" /tmp/pdftext.cache`;
    $pdftext = `cat /tmp/pdftext.cache`;


    $curProxy = 0;

#---- proxylisten
	$proxyList = `curl -s http://www.proxy-listen.de`;
	if ($proxyList =~ m/Proxy-listen.de HTTP..a..br...(.*?)<br..>(.*?)<br..>(.*?)<br..>(.*?)<br..>/gis)
	{
	    $proxies [0] = $1;
	    $proxies [1] = $2;
	    $proxies [2] = $3;
	    $proxies [3] = $4;
#	    print "$1\n$2\n$3\n$4\n";
	    $curProxy = 0;
	    $proxyID = $proxies[$curProxy];
	}
	else
	{
	  die "\nunable to load proxy.\n";
	}

#---- multiproxy
#	$proxyList = `curl -s http://multiproxy.org/txt_anon/proxy.txt`;
#        $proxyList =~ m/([0-9]+?\.[0-9]+?\.[0-9]+?\.[0-9]+?:[0-9]+)/gis;
#	$proxyID = $1;
	
	print "   using proxy $proxyID\n";


    # try to extract some sentences
    $count = 0;
    %paperList = ();
    while ($pdftext =~ m/(([a-z]{2,22}\s){8,12})/gis)
    {
	$curSen = '\"' . $1 . '\"';
	$curSen =~ tr{\n}{ };
	$curSen =~ tr/ /\+/;

	$title = "";
	$author = "";

	# every sentence does vote for some paper
	#print ` echo wget -O - -d   "http://scholar.google.com/scholar?hl=en&q=$curSen&btnG=&as_sdt=1%2C5&as_sdtp="`;
	#$googlesearch = ` wget -q --save-headers  --keep-session-cookies -O -  "http://scholar.google.com/scholar?hl=en&q=$curSen&btnG=&as_sdt=1_5&as_sdtp="`;
#	$googlesearch = `wget -O - http://anonymouse.org/cgi-bin/anon-www_de.cgi/http://scholar.google.com/scholar?q=$curSen`;
#	print `echo http_proxy=http://$proxyID http://scholar.google.com/scholar?q=$curSen`;
	$googlesearch = `http_proxy=http://$proxyID  curl -s --user-agent "Mozilla/4.73 [en] (X11; U; Linux 2.2.15 i686)"  'http://scholar.google.com/scholar?q=$curSen'`;
	print " loaded " . length($googlesearch) . " bytes\n";

	# unreasonable length --> new proxy
	if ((length($googlesearch) < 1000) || ($googlesearch =~ m/www.google.com.sorry/))
	{
	  print "  -- proxy outdated! trying to obtain next one..";
	  $curProxy++;
	  $proxyID = $proxies[$curProxy];
	  next;
	}

	if ($googlesearch =~ m/div.class..gs_r.*?h3.*?a.href.*?>(.*?)<.a>/gis)
	{
	  $title = $1;
	  print "    Title $title\n";
	  $googlesearch =~ m/div.class..gs_a.>(.*?)<.div>/gis;

	  # if the title is strange, we skip the entry
	  next if ($title =~ m/SUGGESTED CITATION/gis);
	  next if ($title =~ m/Related articles/gis);
	  next if ($title =~ m/Create.email.alert/gis);


	  # if we have <a href> in it, remove it
	  $author = $1;
	  if ($author =~ m/<a.href.*?>(.*?)<.a>/gis)
	  {
	    $author = $1;
	  }

	  #take everything until we hit a &
	  $author =~ m/(.*?)\&/gis;

	  $author = $1;
	  print "    Author $author\n";
	  $paperList{"$title.$author"}++;
	}
	else
	{
	  print "  not found.";

	}
	$count++;
	last if ($count > 7);
	print ".";
    }

    $minCount = 2;
    $finalTitle = '';
   for my $key ( keys %paperList ) {
        my $value = $paperList{$key};
	if ($value > $minCount)
	{
	  $finalTitle = $key;
	  $minCount = $value;
	}
    }

    return -1 if ($minCount == 2);
      
    $finalTitle = normalize ($finalTitle);

    print "Final Name: $finalTitle";
    return $finalTitle;
}




sub renameFile {
    my $newname  = $_[1];
    my $filename = $_[0];

    my $randomnumber = int( rand(100000) );

    # add path for now
    $newname = $libDir . '/' . $newname;

    if ( -e $newname ) {
        print "  --$newname exists, ";
        if ( $newname eq $filename ) {
            print "as current filename is also the new one";
            return;
        }

        print "  try to decide if the file are binary equal..";

        if ( md5compare( $filename, $newname ) == 0 ) {

            # same, so we overwrite without blushing faces
            print GREEN, "yes. ", RESET, "so simply overwriting.\n";
        }
        else {
            print RED, "no. ", RESET, "so adding a random number.\n";
            @nameparts = split( /\./, $newname );
            $prelast = scalar(@nameparts) - 2;
            $nameparts[$prelast] .= ".v$randomnumber";
            $newname = join( ".", @nameparts );

            # if it still exists, pech gehabt!
        }
    }

    print GREEN, "  renaming", RESET, " $filename \n    ----> ", GREEN,
      " $newname  \n\n", RESET;

    # for safety we escape spaces
    #	$filename = quotemeta ($filename);
    $output = `mv \"$filename\" \"$newname\"`;
    print $output;
}

sub normalize {
    my $pre = $_[0];
    print "before: $pre\n";

    # escape characters
    $pre =~ s/\&\#[0-9]*;//g;
    $pre =~ s/\-/_/g;
    $pre =~ s/:/_/g;
    $pre =~ s/&gt;/_/g;
    $pre =~ s/&lt;/_/g;
    $pre =~ s/,/_/g;
    $pre =~ s/\?/_/g;
    $pre =~ s/\s/_/g;
    $pre =~ s/\s/_/g;
    $pre =~ s/\&x23[0-9]+;/_/g;
    $pre =~ s/'//g;
    $pre =~ s/\+/plus/g;
    $pre =~ s/@/at/g;
    $pre =~ s/&amp;/and/g;
    $pre =~ s/%//g;
    $pre =~ s/\///g;
    $pre =~ s/\xc3\xb6/o/g;
    $pre =~ s/\(/_/g;
    $pre =~ s/\)/_/g;

    #	$pre =~ s/\x128-\x255//g;
    #	$pre = utf8::decode ($pre);
    $pre = NFD($pre);
    $pre =~ s/[^[:ascii:]]//g;
    $pre =~ s/!/_/g;

    # mmmh..
    $pre =~ s/&Sharp[0-9]*;//g;
    $pre =~ s/&/and/g;

    # _. is not helpful
    $pre =~ s/_\././g;

    # make sure that no twice _ occur no more
    $pre =~ s/__/_/g;
    $pre =~ s/__/_/g;
    $pre =~ s/__/_/g;
    $pre =~ s/^_//g;

    print "    after normalization: $pre\n";

    $result = $pre;
}



sub md5compare {

    #md5test
    my $filename = shift;
    my $newname  = shift;

    my $md51 = `$md5exe $md5options \"$filename\"`;
    my $md52 = `$md5exe $md5options \"$newname\"`;

    $md51 = $1 if ( $md51 =~ m/([0-9a-f]+).*/ );

    $md52 = $1 if ( $md52 =~ m/([0-9a-f]+).*/ );

    if ( $md51 eq $md52 ) {

        # test ok
        return 0;
    }
    else {

        # not ok
        return -1;
    }
}
