function resample_video(infile,tstamps,outfile,outprof,varargin)
    
    % Nearest neighbor temporal resampling of video file

    if ~all(diff(tstamps)>0)
        error('tstamps must be monotonically increasing');
    end
    
    [progfun,varargin]=skim(varargin,'progfun',@(x)isa(x,'function_handle'));
    
    out=VideoWriter(outfile,outprof);
    tmpfile='';
    if strcmpi(out.Filename,infile)
        % The output file has the same name as the input file. This means
        % that the inputfile needs to be replaced. Make up a temporary name
        % for the output now, and afterwards delete the inputfile and
        % rename the temporary file
        tmpfile=[tempname(out.Path) '_' mfilename];
        out=VideoWriter(tmpfile,outprof);
    end
    in=VideoReader(infile);
    
    if ~mod(numel(varargin),2)==0
        error('The number of remaining arguments to pass to VideoWriter should be name-value pairs, but their number is odd.');
    end
    for i=1:2:numel(varargin)
        out.(varargin{i})=varargin{i+1}; % for example 'Quality',100
    end
    
    open(out);
    try
        n_out_frames=round(tstamps(end)*out.FrameRate);
        nearest_frame=readFrame(in);
        in_frame_counter=1;
        for i=1:n_out_frames
            feval(progfun,i,n_out_frames);
            [~,nearest_neighbor]=min(abs(tstamps-i/out.FrameRate));
            if in_frame_counter<nearest_neighbor
                in_frame_counter=nearest_neighbor;
                nearest_frame=readFrame(in); % get the next frame
            end
            writeVideo(out,nearest_frame); % add nearest frame to the output
        end
    catch me
        close(out)
        rethrow(me)
    end
    close(out);
    
    % if the infile and the outfile were the same, replace original with
    % the resampled one
    if ~isempty(tmpfile)
        [ok,msg,msgid]=movefile(tmpfile,infile);
        if ~ok
            error(msgid,msg);
        end
    end
end