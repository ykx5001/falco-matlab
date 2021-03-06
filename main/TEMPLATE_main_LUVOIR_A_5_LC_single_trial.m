% Copyright 2018, by the California Institute of Technology. ALL RIGHTS
% RESERVED. United States Government Sponsorship acknowledged. Any
% commercial use must be negotiated with the Office of Technology Transfer
% at the California Institute of Technology.
% -------------------------------------------------------------------------
%
%--Script to:
%  1) Specify the key parameter values for a Lyot coronagraph.
%  2) Load the rest of the default settings.
%  3) Save out all the input parameters.
%  4) Run a single trial of WFSC using FALCO.
%
% Modified on 2018-03-27 by A.J. Riggs from VC to LC.
% Modified on 2018-03-22 by A.J. Riggs to have default values that can be
%   overwritten if the variable is already defined in falco_config_defaults_AVC.m.
% Modified on 2018-03-01 by Garreth Ruane and A.J. Riggs to be for a vortex coronagraph.
% Created by A.J. Riggs on 2018-01-08.

%% Go the correct starting directory and add all of FALCO to the Matlab path
clear;

if(~isdeployed)
  pwd0 = fileparts(which(mfilename)); %--Path to this file
  cd(pwd0);
  cd ../ %--Go up one step from the "main" directory to the primary FALCO directory
  addpath(genpath(pwd)) %--To find apodizer masks and saved pupils
end

%% Step 1: Define any variable values that will overwrite the defaults (in falco_config_defaults_SPLC)

%%--Record Keeping
mp.TrialNum = 1; %--Always use a diffrent Trial # for different calls of FALCO.
mp.SeriesNum = 1; %--Use the same Series # for sets of similar trials.

%%--WFSC Iterations and Control Matrix Relinearization
mp.Nitr = 10; %--Number of estimation+control iterations to perform
mp.relinItrVec = 1:mp.Nitr;  %--Which correction iterations at which to re-compute the control Jacobian

%%--Special Computational Settings
mp.flagParfor = false; %--whether to use parfor for Jacobian calculation
mp.useGPU = false; %--whether to use GPUs for Jacobian calculation

mp.controller = 'EFC';%'conEFC';  % Controller options: 'EFC' for EFC as an empirical grid search over tuning parametrs, 'conEFC' for constrained EFC using CVX.
% mp.centering = 'pixel'; %--Centering on the arrays at each plane: pixel or interpixel

%%--Coronagraph and Pupil Type
mp.coro = 'LC';   %--Tested Options: 'LC','SPLC','Vortex'
% mp.flagApod = false;
mp.whichPupil = 'LUVOIRA5';

%%--Pupil Plane and DM Plane Properties
mp.d_dm1_dm2 = 1; % distance between DM1 and DM2 (meters)
% mp.d_P2_dm1 = 0; % distance (along +z axis) from P2 pupil to DM1 (meters)

%%--Bandwidth and Wavelength Specs
mp.lambda0 = 600e-9; % central wavelength of bandpass (meters)
mp.fracBW = 0.01;  % fractional bandwidth of correction (Delta lambda / lambda)
mp.Nsbp = 1; % number of sub-bandpasses across correction band 
% mp.Nwpsbp = 1;% number of wavelengths per sub-bandpass. To approximate better each finite sub-bandpass in full model with an average of images at these values. Can be odd or even value.


%%--Pupil Masks
switch mp.whichPupil

    case{'LUVOIRA5'}  % Note:  Nbeam needs to be >~500 to properly resolve segment gaps 
        mp.P1.D = 15.2; %14.9760; %--meters, circumscribing diameter of telescope (used only for mas-to-lambda/D conversion)
        mp.P1.Dfac = 15.2/13.7; %--Ratio of OD_circumscribed to OD_inscribed for the non-circular outer aperture.

        %--Number of pixels across the beam at P1 (the input pupil) and P4 (the Lyot plane)
        mp.P1.full.Nbeam = 1000; %--Number of pixels across the actual diameter of the beam/aperture (independent of beam centering
        mp.P1.compact.Nbeam = 400;
        
        %--Lyot Stop parameters
        mp.P4.IDnorm = 0.40; %--Inner diameter of Lyot stop (relative to circumscribed outer diameter of telescope pupil)
        mp.P4.ODnorm = 0.80; %--Outer diameter of Lyot stop (relative to circumscribed outer diameter of telescope pupil)
        
    case 'LUVOIR_B_offaxis' % Note:  Nbeam needs to be >~500 to properly resolve segment gaps 
        mp.P1.D = 7.989; %--meters, circumscribed. The segment size is 0.955 m, flat-to-flat, and the gaps are 6 mm.
        
        mp.P1.full.Nbeam = 1000; %--Number of pixels across the actual diameter of the beam/aperture (independent of beam centering
        mp.P4.full.Nbeam = mp.P1.full.Nbeam; % P4 must be the same as P1 for LC. 
        
        mp.P1.compact.Nbeam = 500;
        mp.P4.compact.Nbeam = mp.P1.compact.Nbeam; % P4 must be the same as P1 for LC.

        mp.P3.IDnorm = 0;
        mp.P3.ODnorm = 0.84;
        
        mp.P4.IDnorm = 0; %--Inner diameter of Lyot stop (relative to circumscribed outer diameter of telescope pupil)
        mp.P4.ODnorm = 0.82; %--Outer diameter of Lyot stop (relative to circumscribed outer diameter of telescope pupil)
        
end

%%--DMs
DM.dm_ind = [1 2]; % vector of which DMs to use for control.
DM.dm1.Nact = 64; % number of actuators across DM1
DM.dm2.Nact = 64; % number of actuators across DM2
mp.P2.D =     (DM.dm1.Nact-2)*1e-3; % beam diameter at pupil closest to the DMs  (meters). Assumes Xinetics inter-actuator pitch of 1.000 mm.

%%--Controller Settings
switch mp.controller
    case{'EFC'} % 'EFC' = empirical grid search over both overall scaling coefficient and Lagrange multiplier
        % Take images for different Lagrange multiplier values and overall command gains and pick the value pair that gives the best contrast
        cp.muVec = 10.^(5:-1:1);
        cp.dmfacVec = 1;%[0.7, 1]; %[0.5, 1, 2];
        
    case{'conEFC'} %--Constrained EFC, written by He Sun of Princeton University
        DM.dm1.dVpvMax = 30;
        DM.dm2.dVpvMax = 30;
        cp.dmfacVec = 1;
end
%--Voltage range restrictions
DM.dm1.maxAbsV = 250./2.;
DM.dm2.maxAbsV = 250./2.;


%%--Tip/Tilt Control
mp.NlamForTT = 1; %--Number of wavelengths to control  tip/tilt at. 0,1, 2, 3, or inf (for all)
mp.Ntt = 1; %--Number of tip/tilt offsets, including 0 (so always set >=1). 1, 4, or 5
mp.TToffset = 1; %--tip/tilt offset (mas)





%% Coronagraphic Mask Properties:

% mp.flagDM1stop = false; %--logical flag whether to include the stop at DM1 or not
% mp.flagDM2stop = false; %--logical flag whether to include the stop at DM2 or not


%% Final Focal Plane (F4) Properties

% %%--Final Focal Plane (F4) Properties
% mp.F4.compact.res = 3; %--Pixels per lambda_c/D
% mp.F4.full.res = 6; %--Pixels per lambda_c/D
% mp.F4.FOV = 1 + mp.F4.corr.Rout; % minimum desired field of view (along both axes) in lambda0/D


%% Tip/Tilt, Spatial, and Chromatic Weighting of the Control Jacobian  #NEWFORTIPTILT
% mp.Ntt = 1; %--Number of tip/tilt offsets, including 0 (so always set >=1). 1, 4, or 5
% mp.NlamForTT = 1; %--Number of wavelengths to compute tip/tilt at. 0,1, 2, 3, or inf (for all)
% mp.TToffset = 1; %--tip/tilt offset in mas
% 
% %--Spatial pixel weighting
% mp.WspatialDef = [mp.F4.corr.Rin, mp.F4.corr.Rin+2, 1];  %--spatial control Jacobian weighting by annulus: [Inner radius, outer radius, intensity weight; (as many rows as desired)]
% 
% %--Chromatic weighting


%% Part 2: Call the function to define the rest of the variables and initialize the workspace
if(exist('mp','var')==false); mp.dummy = 1; end
if(exist('cp','var')==false); cp.dummy = 1; end
if(exist('ep','var')==false); ep.dummy = 1; end
if(exist('DM','var')==false); DM.dummy = 1; end

[mp,cp,ep,DM] = falco_config_defaults_LC(mp,cp,ep,DM); %--Load defaults for undefined values


%% Part 3: Save the config file    
mp.runLabel = ['Series',num2str(mp.SeriesNum,'%04d'),'_Trial',num2str(mp.TrialNum,'%04d_'),...
    mp.coro,'_',mp.whichPupil,'_',num2str(numel(DM.dm_ind)),'DM',num2str(DM.dm1.Nact),'_z',num2str(mp.d_dm1_dm2),...
    '_IWA',num2str(mp.F4.corr.Rin),'_OWA',num2str(mp.F4.corr.Rout),...
    '_',num2str(mp.Nsbp),'lams',num2str(round(1e9*mp.lambda0)),'nm_BW',num2str(mp.fracBW*100),...
    '_',mp.controller];
fn_config = ['data/configs/',mp.runLabel,'.mat'];
save(fn_config)
fprintf('Saved the config file: \t%s\n',fn_config)


%% Part 4: Run the WFSC trial

falco_wfsc_loop(fn_config,'PLOT'); %--Plot progress
% falco_wfsc_loop(fn_config); %--Don't plot anything





