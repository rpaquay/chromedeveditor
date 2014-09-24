set SVN_REVISION=40638
rmdir /s /q analysis_server
if errorlevel 1 goto error
rmdir /s /q analyzer_clone
if errorlevel 1 goto error
call svn co -r %SVN_REVISION% https://dart.googlecode.com/svn/branches/bleeding_edge/dart/pkg/analysis_server
call svn co -r %SVN_REVISION% https://dart.googlecode.com/svn/branches/bleeding_edge/dart/pkg/analyzer analyzer_clone

goto end

:error
echo "Error. Try running again."
goto end

:end


