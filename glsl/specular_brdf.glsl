
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// "Specular" dielectric microfacet BRDF
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

void specular_ndf_roughnesses(out float alpha_x, out float alpha_y)
{
    float rsqr = sqr(specular_roughness);
    alpha_x = rsqr * sqrt(2.0/(1.0 + sqr(1.0 - specular_anisotropy)));
    alpha_y = (1.0 - specular_anisotropy) * alpha_x;
}

vec3 specular_brdf_evaluate(in vec3 pW, in Basis basis, in vec3 winputL, in vec3 woutputL,
                            inout int rndSeed)
{
    float n_exterior = 1.0;
    float n_interior = specular_ior;
    float eta_ti = n_interior/n_exterior;
    if (abs(eta_ti - 1.0) < 1.0e-4)
    {
        // degenerate case of index-matched interface, BRDF goes to zero
        return vec3(0.0);
    }

    bool transmitted = woutputL.z * winputL.z < 0.0;
    if (transmitted)
        return vec3(0.0);

    // Construct basis such that x, y are aligned with the T, B in the local, rotated frame
    LocalFrameRotation rotation = getLocalFrameRotation(PI2 * specular_rotation);
    vec3 winputR  = localToRotated(winputL,  rotation);
    vec3 woutputR = localToRotated(woutputL, rotation);

    // Compute the NDF roughnesses in the rotated frame
    float alpha_x, alpha_y;
    specular_ndf_roughnesses(alpha_x, alpha_y);

    // Compute the micronormal mR in the local (rotated) frame, from the reflection half-vector
    vec3 mR = normalize(woutputR + winputR);
    
    // Compute NDF
    float D = ggx_ndf_eval(mR, alpha_x, alpha_y);

    // Compute shadowing-masking term
    float G2 = ggx_G2(winputR, woutputR, mR, alpha_x, alpha_y);

    // Compute Fresnel factor for the dielectric reflection
    vec3 F = specular_weight * specular_color * FresnelDielectricReflectance(abs(winputR.z), specular_ior);

    // Thus evaluate BRDF
    return F * D * G2 / max(4.0*abs(woutputL.z)*abs(winputL.z), DENOM_TOLERANCE);
}

vec3 specular_brdf_sample(in vec3 pW, in Basis basis, in vec3 winputL,
                          out vec3 woutputL, out float pdf_woutputL, inout int rndSeed)
{
    float n_exterior = 1.0;
    float n_interior = specular_ior;
    float eta_ti = n_interior/n_exterior;
    if (abs(eta_ti - 1.0) < 1.0e-4)
    {
        // degenerate case of index-matched interface, BRDF goes to zero
        pdf_woutputL = 1.0;
        return vec3(0.0);
    }

    // Construct basis such that x, y are aligned with the T, B in the rotated frame
    LocalFrameRotation rotation = getLocalFrameRotation(PI2 * specular_rotation);
    vec3 winputR = localToRotated(winputL, rotation);

    // Compute the NDF roughnesses in the rotated frame
    float alpha_x, alpha_y;
    specular_ndf_roughnesses(alpha_x, alpha_y);

    // Sample local microfacet normal mR, according to Heitz "Sampling the GGX Distribution of Visible Normals"
    vec3 mR = ggx_ndf_sample(winputR, alpha_x, alpha_y, rndSeed);

    // Compute woutputR (and thus woutputL) by reflecting winputR about mR
    vec3 woutputR = -winputR + 2.0*dot(winputR, mR)*mR;
    if (woutputR.z < DENOM_TOLERANCE) return vec3(0.0);
    woutputL = rotatedToLocal(woutputR, rotation);

    // Compute NDF, and "distribution of visible normals" DV
    float D = ggx_ndf_eval(mR, alpha_x, alpha_y);
    float DV = ggx_G1(winputR, mR, alpha_x, alpha_y) * max(0.0, dot(winputR, mR)) * D / max(DENOM_TOLERANCE, winputR.z);

    // Thus compute PDF of woutputL sample
    float dwh_dwo = 1.0 / max(abs(4.0*dot(winputR, mR)), DENOM_TOLERANCE); // Jacobian of the half-direction mapping
    pdf_woutputL = DV * dwh_dwo;

    // Compute shadowing-masking term
    float G2 = ggx_G2(winputR, woutputR, mR, alpha_x, alpha_y);

    // Compute Fresnel factor for the dielectric reflection
    vec3 F = specular_weight * specular_color * FresnelDielectricReflectance(abs(winputR.z), specular_ior);

    // Thus evaluate BRDF
    return F * D * G2 / max(4.0*abs(woutputL.z)*abs(winputL.z), DENOM_TOLERANCE);
}

float specular_brdf_pdf(in vec3 pW, in Basis basis, in vec3 winputL, in vec3 woutputL)
{
    bool transmitted = woutputL.z * winputL.z < 0.0;
    if (transmitted)
        return PDF_EPSILON;

    float n_exterior = 1.0;
    float n_interior = specular_ior;
    float eta_ti = n_interior/n_exterior;
    if (abs(eta_ti - 1.0) < 1.0e-4)
    {
        // degenerate case of index-matched interface, BRDF goes to zero
        return 1.0;
    }

    // Construct basis such that x, y are aligned with the T, B in the local, rotated frame
    LocalFrameRotation rotation = getLocalFrameRotation(PI2 * specular_rotation);
    vec3 winputR  = localToRotated(winputL,  rotation);
    vec3 woutputR = localToRotated(woutputL, rotation);

    // Compute the NDF roughnesses in the rotated frame
    float alpha_x, alpha_y;
    specular_ndf_roughnesses(alpha_x, alpha_y);

    // Compute the local micronormal from the reflection half-vector
    vec3 mR = normalize(winputR + woutputR);

    // Compute NDF, and "distribution of visible normals" DV
    float D = ggx_ndf_eval(mR, alpha_x, alpha_y);
    float DV = ggx_G1(winputR, mR, alpha_x, alpha_y) * max(0.0, dot(winputR, mR)) * D / winputR.z;

    // Thus compute PDF of woutputL sample
    float dwh_dwo = 1.0 / max(abs(4.0*dot(winputR, mR)), DENOM_TOLERANCE); // Jacobian of the half-direction mapping
    float pdf_woutputL = DV * dwh_dwo;
    return pdf_woutputL;
}

vec3 specular_brdf_albedo(in vec3 pW, in Basis basis, in vec3 winputL,
                          inout int rndSeed)
{
    float n_exterior = 1.0;
    float n_interior = specular_ior;
    float eta_ti = n_interior/n_exterior;
    if (abs(eta_ti - 1.0) < 1.0e-4)
    {
        // degenerate case of index-matched interface, BRDF goes to zero
        return vec3(0.0);
    }

    // Approximate albedo via Monte-Carlo sampling:
    const int num_samples = 4;
    vec3 albedo = vec3(0.0);
    for (int n=0; n<num_samples; ++n)
    {
        vec3 woutputL;
        float pdf_woutputL;
        vec3 f = specular_brdf_sample(pW, basis, winputL, woutputL, pdf_woutputL, rndSeed);
        if (length(f) > RADIANCE_EPSILON)
            albedo += f * abs(woutputL.z) / max(DENOM_TOLERANCE, pdf_woutputL);
    }
    albedo /= float(num_samples);
    return albedo;
}