% Copyright 2018, by the California Institute of Technology. ALL RIGHTS
% RESERVED. United States Government Sponsorship acknowledged. Any
% commercial use must be negotiated with the Office of Technology Transfer
% at the California Institute of Technology.
% -------------------------------------------------------------------------
%
% function Eout = model_full_VC(mp, DM, modvar)
%--Full-knowledge optical model.
%    --> Not used by the estimator and controller.
%    --> Only used to create simulated intensity images.
%
% REVISION HISTORY:
% --------------
% Modified on 2017-10-17 by A.J. Riggs to have model_full.m be a wrapper. All the 
%  actual full models, including this one, have been moved to sub-routines for clarity.
% Modified by A.J. Riggs from hcil_simTestbed.m to model_full.m.
% Modified on 2015-02-18 by A.J. Riggs from hcil_model.m to hcil_simTestbed.m to inclue
%  extra errors in the model to simulate the actual testbed for fake images.
%
% ---------------
% INPUTS:
% -mp = structure of model parameters
% -DM = structure of DM settings
% -modvar = structure of model variables
%
%
% OUTPUTS:
% -Eout
%
% modvar structure fields (4):
% -sbpIndex
% -wpsbpIndex
% -whichSource
% -flagGenMat


function Eout = model_full_VC(mp, DM, modvar)

lambda = mp.sbp_center_vec(modvar.sbpIndex)*mp.lamFac_vec(modvar.wpsbpIndex);
mirrorFac = 2; % Phase change is twice the DM surface height.
NdmPad = DM.full.NdmPad;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Input E-fields
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%--Set the point source as the exoplanet or the star
if strcmpi(modvar.whichSource, 'exoplanet') %--Don't include tip/tilt jitter for planet wavefront since the effect is minor
    %--The planet does not move in sky angle, so the actual tip/tilt angle needs to scale inversely with wavelength.
    planetAmp = sqrt(mp.c_planet);  % Scale the E field to the correct contrast
    planetPhase = (-1)*(2*pi*(mp.x_planet*mp.P2.full.XsDL + mp.y_planet*mp.P2.full.YsDL));
    Ein = planetAmp*exp(1i*planetPhase*mp.lambda0/lambda);

elseif strcmpi(modvar.whichSource,'offaxis') %--Use for throughput calculations 
    TTphase = (-1)*(2*pi*(modvar.x_offset*mp.P2.full.XsDL + modvar.y_offset*mp.P2.full.YsDL));
    Ett = exp(1i*TTphase*mp.lambda0/lambda);
    Ein = Ett.*mp.P1.full.E(:,:,modvar.wpsbpIndex,modvar.sbpIndex); 
        
else % Default to using the starlight
    %--Include the tip/tilt in the input stellar wavefront
    if(isfield(mp,'ttx'))
        %--Scale by lambda/lambda0 because ttx and tty are in lambda0/D
        x_offset = mp.ttx(modvar.ttIndex);
        y_offset = mp.tty(modvar.ttIndex);

        TTphase = (-1)*(2*pi*(x_offset*mp.P2.full.XsDL + y_offset*mp.P2.full.YsDL));
        Ett = exp(1i*TTphase*mp.lambda0/lambda);
        Ein = Ett.*mp.P1.full.E(:,:,modvar.wpsbpIndex,modvar.sbpIndex);  

    else %--Backward compatible with code without tip/tilt offsets in the Jacobian
%         Ein = mp.Estar(:,:,modvar.wpsbpIndex,modvar.sbpIndex);  
        Ein = mp.P1.full.E(:,:,modvar.wpsbpIndex,modvar.sbpIndex);  
    end
end

fn_PSD = sprintf('maps_PSD_%s.mat',mp.coro);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Masks and DM surfaces
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


if(any(DM.dm_ind==1))
    if( isfield(DM.dm1,'surfM') );   DM1surf = padOrCropEven(DM.dm1.surfM, NdmPad);
    else                            DM1surf = falco_gen_dm_surf(DM.dm1,DM.dm1.dx,NdmPad); end
else DM1surf = 0;
end
if(any(DM.dm_ind==2))
    if( isfield(DM.dm2,'surfM') );   DM2surf = padOrCropEven(DM.dm2.surfM, NdmPad);
    else                            DM2surf = falco_gen_dm_surf(DM.dm2,DM.dm2.dx,NdmPad); end
else DM2surf = 0;
end


if(any(DM.dm_ind==9)) %--If using DM9, apply DM9phase  
    error('DM9 not implemented with vortex yet. ');
end


pupil = padOrCropEven(mp.P1.full.mask,NdmPad);
Ein = padOrCropEven(Ein,NdmPad);

if(mp.flagDM1stop); DM1stop = padOrCropEven(mp.dm1.full.mask, NdmPad); else DM1stop = 1; end
if(mp.flagDM2stop); DM2stop = padOrCropEven(mp.dm2.full.mask, NdmPad); else DM2stop = 1; end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Propagation: entrance pupil, 2 DMs, (optional) apodizer, vortex FPM, LS, and final focal plane
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%--Define pupil P1 and Propagate to pupil P2
EP1 = pupil.*Ein; %--E-field at pupil plane P1
EP2 = propcustom_2FT(EP1,mp.centering); %--Forward propagate to the next pupil plane (P2) by rotating 180 deg.

if(mp.useGPU)
    EP2 = gpuArray(EP2);
end

%--Propagate from P2 to DM1, and apply DM1 surface and aperture stop
if( abs(mp.d_P2_dm1)~=0 ); Edm1 = propcustom_PTP(EP2,mp.P2.full.dx*NdmPad,lambda,mp.d_P2_dm1); else Edm1 = EP2; end  %--E-field arriving at DM1
Edm1 = DM1stop.*exp(mirrorFac*2*pi*1i*DM1surf/lambda).*Edm1; %--E-field leaving DM1

%--Propagate from DM1 to DM2, and apply DM2 surface and aperture stop
Edm2 = propcustom_PTP(Edm1,mp.P2.full.dx*NdmPad,lambda,mp.d_dm1_dm2); 
Edm2 = DM2stop.*exp(mirrorFac*2*pi*1i*DM2surf/lambda).*Edm2;

%--Back-propagate to pupil P2
if( mp.d_P2_dm1 + mp.d_dm1_dm2 == 0 ); EP2eff = Edm2; else EP2eff = propcustom_PTP(Edm2,mp.P2.full.dx*NdmPad,lambda,-1*(mp.d_dm1_dm2 + mp.d_P2_dm1)); end %--Back propagate to pupil P2

%--Rotate 180 degrees to propagate to pupil P3
EP3 = propcustom_2FT(EP2eff, mp.centering);

%--Apply the apodizer mask (if there is one)
if(mp.flagApod)
    EP3 = padOrCropEven(mp.P3.full.mask,mp.P3.full.Narr).*padOrCropEven(EP3, mp.P3.full.Narr); %--Apply apodizer mask.
else
    EP3 = padOrCropEven(EP3,2^nextpow2(mp.P1.full.Narr)); %--Crop down for the MFTs if there isn't an apodizer mask
end

%--Do NOT apply FPM if normalization value is being found
if(isfield(modvar,'flagGetNormVal'))
    if(modvar.flagGetNormVal==true)
        EP4 = propcustom_2FT(EP3, mp.centering);
    else
        EP4 = propcustom_mft_Pup2Vortex2Pup( EP3, mp.F3.VortexCharge, mp.P1.full.Nbeam/2, 0.3, 5, mp.useGPU );  %--MFTs
    end
else
    EP4 = propcustom_mft_Pup2Vortex2Pup( EP3, mp.F3.VortexCharge, mp.P1.full.Nbeam/2, 0.3, 5, mp.useGPU ); %--MFTs
end    

EP4 = mp.P4.full.croppedMask.*padOrCropEven(EP4,mp.P4.full.Narr);

%--MFT from Lyot Stop to final focal plane (i.e., P4 to F4)
EF4 = propcustom_mft_PtoF(EP4,mp.fl,lambda,mp.P4.full.dx,mp.F4.full.dxi,mp.F4.full.Nxi,mp.F4.full.deta,mp.F4.full.Neta);


%--Don't apply FPM if normalization value is being found, or if the flag doesn't exist (for testing only)
Eout = EF4; %--Don't normalize if normalization value is being found
if(isfield(modvar,'flagGetNormVal'))
    if(modvar.flagGetNormVal==false)
        Eout = EF4/sqrt(mp.F4.full.I00(modvar.sbpIndex)); %--Apply normalization
    end
elseif(isfield(mp.F4.full,'I00'))
    Eout = EF4/sqrt(mp.F4.full.I00(modvar.sbpIndex)); %--Apply normalization
end



end % End of function


    
