set SVN_REVISION=40638
rmdir /s /q analysis_server
svn co -r %SVN_REVISION% https://dart.googlecode.com/svn/branches/bleeding_edge/dart/pkg/analysis_server
