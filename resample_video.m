function resample_video(infile,tstamps,fps,profile,varargin)
    
    %resample_video - Nearest neighbor temporal resampling of video files
    %
    %   resample_video(infile,tstamps,fps,profile,varargin)
    %
    %   infile - filename of video file to be resampled
    %   tstamps - array with timestamps at which the frames in infile were
    %       collected (or any monotonically increasing array with a value
    %       for each infile frame if you feel creative)
    %   fps - the framerate of the output file
    %   profile - a video profile, or the format of the output file. For
    %       example 'MPEG-4' (Refer to help VideoWriter for a list of
    %       profiles).
    %
    %   Optional Name,Value pairs: 
    %
    %   'outfile','' - optional output filename. If the outfile is not
    %       specified or the same as the infile, the conversion will first
    %       stream to an intermediate file which will at end replace the
    %       infile. The intermediate file will then be replaced.
    %   'progfun','' - Use this to show a progress indicator and a cancel
    %       option. Optional handle to a custom function of the form
    %       c=fun(i,n) that will be called before every video frame where i
    %       is the input frame number about to resampled and n the total
    %       number of frames in the input video, c is an output boolean
    %       that indicates if the user requested cancelation of the
    %       process.
    %   
    %   Jacob Duijnhouwer 2020-03-16
    
    p=inputParser;
    p.addRequired('infile',@ischar);
    p.addRequired('tstamps',@isnumeric); % frame times in seconds
    p.addRequired('fps',@(x)and(isnumeric(x),x>0)); % desired frames rate of output file
    p.addRequired('profile',@ischar);
    p.addParameter('outfile','',@ischar);
    p.addParameter('vidprops',struct,@isstruct);
    p.addParameter('progfun','',@(x)isa(x,'function_handle'));
    p.parse(infile,tstamps,fps,profile,varargin{:});
   
    if ~all(diff(tstamps)>0)
        error('frame times array in seconds (arg #2) must be increasing monotonically');
    end
    
    fid_in=VideoReader(infile);
    
    outfile=p.Results.outfile;
    if isempty(outfile)
        outfile=infile; % overwrite
    end

    if strcmpi(infile,outfile)
        % The output file has the same name as the input file. This means
        % that the inputfile needs to be replaced. Make up a temporary name
        % for the output now, and afterwards delete the inputfile and
        % rename the temporary file
        folder=fileparts(infile);
        if isempty(folder)
            folder=pwd;
        end
        tmpfile=[tempname(folder) '_' mfilename];
        fid_out=VideoWriter(tmpfile,profile);
    else
        fid_out=VideoWriter(outfile,profile);
    end
    % Se the optional video properties from vidprops struct. which are
    % valid depends on the profile in use. MPEG-4 has Quality for example.
    % All have FrameRate, but see below
    flds=fieldnames(p.Results.vidprops);
    for i=1:numel(flds)
        if fid_out.(flds{i})~=p.Results.vidprops.(flds{i})
            % only write when different to prevent error like 'Setting the
            % CompressionRatio when LosslessCompression is enable is not
            % allowed.'
            fid_out.(flds{i})=p.Results.vidprops.(flds{i});
        end
    end
    % All video profiles have the settable property FrameRate. If it was in
    % vidprops it will now be overruled by required argumen fps
    fid_out.FrameRate=fps;
    
    % Start writing the frames to outfile
    open(fid_out);
    try
        % within try-catch so we can close(fid_out) upon error
        n_out_frames=round(tstamps(end)*fid_out.FrameRate);
        nearest_frame=readFrame(fid_in);
        in_frame_counter=1;
        canceled_by_user=false;
        for i=1:n_out_frames
            canceled_by_user=feval(p.Results.progfun,i,n_out_frames);
            if canceled_by_user
                break
            end
            [~,nearest_neighbor]=min(abs(tstamps-i/fid_out.FrameRate));
            if in_frame_counter<nearest_neighbor
                in_frame_counter=nearest_neighbor;
                nearest_frame=readFrame(fid_in); % get the next frame
            end
            writeVideo(fid_out,nearest_frame); % add nearest frame to the output
        end
    catch me
        close(fid_out)
        rethrow(me)
    end
    close(fid_out);
    delete(fid_in); % free the handle (otherwise can't move file on top of it)
    
    % if the infile and the outfile were the same, replace original with
    % the resampled one. unless user canceled, then just delete it.
    tmpfile=fullfile(fid_out.Path,fid_out.Filename);
    if strcmpi(infile,outfile) && ~canceled_by_user
        [ok,msg,msgid]=movefile(tmpfile,infile);
        if ~ok
            error(msgid,msg);
        end
    elseif canceled_by_user
        delete(tmpfile)
    end      
end
