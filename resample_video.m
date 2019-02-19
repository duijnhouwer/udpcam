function resample_video(infile,tstamps,fps,profile,varargin)
    
    % Nearest neighbor temporal resampling of video file
    % If the infile is empty or the same as the outfile, the conversion
    % will first stream to an intermediate file which will at end replace
    % the infile. The intermediate file will then be replaced.
    
    p=inputParser;
    p.addRequired('infile',@ischar);
    p.addRequired('tstamps',@isnumeric); % frame times in seconds
    p.addRequired('fps',@(x)and(isnumeric(x),x>0)); % output frames per seconds
    p.addRequired('profile',@ischar);
    p.addParameter('out','',@ischar);
    p.addParameter('vidprops',struct,@isstruct);
    p.addParameter('progfun','',@(x)isa(x,'function_handle'));
    p.parse(infile,tstamps,fps,profile,varargin{:});
   
    if ~all(diff(tstamps)>0)
        error('frame times array in seconds (arg #2) must be increasing monotonically');
    end
    
    fin=VideoReader(infile);
    
    outfile=p.Results.out;
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
        fout=VideoWriter(tmpfile,profile);
    else
        fout=VideoWriter(outfile,profile);
    end
    % Se the optional video properties from vidprops struct. which are
    % valid depends on the profile in use. MPEG-4 has Quality for example.
    % All have FrameRate, but see below
    flds=fieldnames(p.Results.vidprops);
    for i=1:numel(flds)
        if fout.(flds{i})~=p.Results.vidprops.(flds{i})
            % only write when different to prevent error like 'Setting the
            % CompressionRatio when LosslessCompression is enable is not
            % allowed.'
            fout.(flds{i})=p.Results.vidprops.(flds{i});
        end
    end
    % All video profiles have the settable property FrameRate. If it was in
    % vidprops it will now be overruled by required argumen fps
    fout.FrameRate=fps;
    
    % Start writing the frames to out
    open(fout);
    try
        % withing try-catch so we can close(out) upon error
        n_out_frames=round(tstamps(end)*fout.FrameRate);
        nearest_frame=readFrame(fin);
        in_frame_counter=1;
        canceled_by_user=false;
        for i=1:n_out_frames
            canceled_by_user=feval(p.Results.progfun,i,n_out_frames);
            if canceled_by_user
                break
            end
            [~,nearest_neighbor]=min(abs(tstamps-i/fout.FrameRate));
            if in_frame_counter<nearest_neighbor
                in_frame_counter=nearest_neighbor;
                nearest_frame=readFrame(fin); % get the next frame
            end
            writeVideo(fout,nearest_frame); % add nearest frame to the output
        end
    catch me
        close(fout)
        rethrow(me)
    end
    close(fout);
    delete(fin); % free the handle (otherwise can't move file on top of it)
    
    % if the infile and the outfile were the same, replace original with
    % the resampled one. unless user canceled, then just delete it.
    tmpfile=fullfile(fout.Path,fout.Filename);
    if strcmpi(infile,outfile) && ~canceled_by_user
        [ok,msg,msgid]=movefile(tmpfile,infile);
        if ~ok
            error(msgid,msg);
        end
    elseif canceled_by_user
        delete(tmpfile)
    end
        
end
