
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// OpenPBR BSDF
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

const int ID_FUZZ_BRDF = 0;
const int ID_COAT_BRDF = 1;
const int ID_META_BRDF = 2;
const int ID_SPEC_BRDF = 3;
const int ID_SPEC_BTDF = 4;
const int ID_DIFF_BRDF = 5;
const int ID_SSSC_BTDF = 6;
const int NUM_LOBES    = 7;

// Weight multipliers of individual BSDF lobes
struct LobeWeights
{   
    vec3 m[7];
};

// Albedos of individual BDSF lobes
struct LobeAlbedos
{ 
    vec3 m[7];
};

// Probabilities of individual BDSF lobes
struct LobeProbs
{ 
    float m[7];
};

LobeWeights lobe_weights;
LobeAlbedos lobe_albedos;
LobeProbs   lobe_probs;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// OpenPBR BSDF: preparation
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Construct weights of individual BSDF lobes, according to OpenPBR surface model (in the non-reciprocal albedo-scaling approximation).
// Note that this requires computing the albedos of some of the lobes.
void openpbr_lobe_weights(in vec3 pW, in Basis basis, in vec3 winputL, inout int rndSeed,
                          inout LobeWeights weights, inout LobeAlbedos albedos)
{
    /////////////////////////////////////////////////////////////////////
    // Surface
    /////////////////////////////////////////////////////////////////////

    // Fuzz BRDF
    weights.m[ID_FUZZ_BRDF] = vec3(0.0); // fuzz_weight;
    if (maxComponent(weights.m[ID_FUZZ_BRDF]) > 0.0) albedos.m[ID_FUZZ_BRDF] = vec3(0.0); //fuzz_brdf_albedo(pW, basis, winputL, rndSeed);
    else                                             albedos.m[ID_FUZZ_BRDF] = vec3(0.0);
    
        /////////////////////////////////////////////////////////////////////
        // Coated base
        /////////////////////////////////////////////////////////////////////

        // Coat BRDF
        vec3 w_coated_base = vec3(1.0); //mix(vec3(1.0), vec3(1.0) - albedos.a_fuzz_brdf, F)
        weights.m[ID_COAT_BRDF] = w_coated_base * coat_weight;
        if (maxComponent(weights.m[ID_COAT_BRDF]) > 0.0) albedos.m[ID_COAT_BRDF] = coat_brdf_albedo(pW, basis, winputL, rndSeed);
        else                                             albedos.m[ID_COAT_BRDF] = vec3(0.0);

            /////////////////////////////////////////////////////////////////////
            // Base substrate
            /////////////////////////////////////////////////////////////////////

            vec3 w_base_substrate = w_coated_base * mix(vec3(1.0), coat_color*(vec3(1.0) - albedos.m[ID_COAT_BRDF]), coat_weight);

            // Metal BRDF
            weights.m[ID_META_BRDF] = w_base_substrate * base_metalness;

                /////////////////////////////////////////////////////////////////////
                // Dielectric base
                /////////////////////////////////////////////////////////////////////

                    vec3 w_dielectric_base = w_base_substrate * vec3(max(0.0, 1.0 - base_metalness));

                    // Specular BRDF
                    weights.m[ID_SPEC_BRDF] = w_dielectric_base;
                    if (maxComponent(weights.m[ID_SPEC_BRDF]) > 0.0) albedos.m[ID_SPEC_BRDF] = specular_brdf_albedo(pW, basis, winputL, rndSeed);
                    else                                             albedos.m[ID_SPEC_BRDF] = vec3(0.0);

                    //////////////////////////////////////////////
                    // Translucent dielectric base
                    //////////////////////////////////////////////

                    // Specular BTDF
                    weights.m[ID_SPEC_BTDF] = w_dielectric_base * transmission_weight;

                    //////////////////////////////////////////////
                    // Opaque dielectric base
                    //////////////////////////////////////////////

                        vec3 w_opaque_dielectric_base = w_dielectric_base * (1.0 - transmission_weight);

                        // Diffuse BRDF
                        weights.m[ID_DIFF_BRDF] = w_opaque_dielectric_base * (1.0 - subsurface_weight) * (vec3(1.0) - albedos.m[ID_SPEC_BRDF]);

                        // Subsurface BSSRDF
                        weights.m[ID_SSSC_BTDF] = w_opaque_dielectric_base * subsurface_weight;


}

// Compute remaining albedos that were not computed in openpbr_lobe_weights
void openpbr_lobe_albedos(in vec3 pW, in Basis basis, in vec3 winputL, inout int rndSeed, in LobeWeights weights, 
                          inout LobeAlbedos albedos)
{
    if (maxComponent(weights.m[ID_META_BRDF]) > 0.0) albedos.m[ID_META_BRDF] = metal_brdf_albedo(pW, basis, winputL, rndSeed);
    else                                             albedos.m[ID_META_BRDF] = vec3(0.0);
    if (maxComponent(weights.m[ID_DIFF_BRDF]) > 0.0) albedos.m[ID_DIFF_BRDF] = diffuse_brdf_albedo(pW, basis, winputL, rndSeed);
    else                                             albedos.m[ID_DIFF_BRDF] = vec3(0.0);
    //if (maxComponent(weights.m[ID_SSSC_BTDF]) > 0.0) albedos.m[ID_SSSC_BTDF] = subsurface_btdf_albedo(pW, basis, winputL, rndSeed);
    //else                                             albedos.m[ID_SSSC_BTDF] = vec3(0.0);
    if (maxComponent(weights.m[ID_SPEC_BTDF]) > 0.0) albedos.m[ID_SPEC_BTDF] = specular_btdf_albedo(pW, basis, winputL, rndSeed);
    else                                             albedos.m[ID_SPEC_BTDF] = vec3(0.0);
}

void openpbr_lobe_probabilities(in LobeWeights weights, inout LobeAlbedos albedos,
                                inout LobeProbs probs)
{
    // Compute probability of sampling each lobe, according to its albedo
    float W_total = 0.0;
    probs.m[ID_FUZZ_BRDF] = length(weights.m[ID_FUZZ_BRDF] * albedos.m[ID_FUZZ_BRDF]); W_total += probs.m[ID_FUZZ_BRDF];
    probs.m[ID_COAT_BRDF] = length(weights.m[ID_COAT_BRDF] * albedos.m[ID_COAT_BRDF]); W_total += probs.m[ID_COAT_BRDF];
    probs.m[ID_META_BRDF] = length(weights.m[ID_META_BRDF] * albedos.m[ID_META_BRDF]); W_total += probs.m[ID_META_BRDF];
    probs.m[ID_SPEC_BRDF] = length(weights.m[ID_SPEC_BRDF] * albedos.m[ID_SPEC_BRDF]); W_total += probs.m[ID_SPEC_BRDF];
    probs.m[ID_SPEC_BTDF] = length(weights.m[ID_SPEC_BTDF] * albedos.m[ID_SPEC_BTDF]); W_total += probs.m[ID_SPEC_BTDF];
    probs.m[ID_DIFF_BRDF] = length(weights.m[ID_DIFF_BRDF] * albedos.m[ID_DIFF_BRDF]); W_total += probs.m[ID_DIFF_BRDF];
    probs.m[ID_SSSC_BTDF] = length(weights.m[ID_SSSC_BTDF] * albedos.m[ID_SSSC_BTDF]); W_total += probs.m[ID_SSSC_BTDF];
    W_total = max(DENOM_TOLERANCE, W_total);
    probs.m[ID_FUZZ_BRDF] /= W_total;
    probs.m[ID_COAT_BRDF] /= W_total;
    probs.m[ID_META_BRDF] /= W_total;
    probs.m[ID_SPEC_BRDF] /= W_total;
    probs.m[ID_SPEC_BTDF] /= W_total;
    probs.m[ID_DIFF_BRDF] /= W_total;
    probs.m[ID_SSSC_BTDF] /= W_total;
}

void openpbr_prepare(in vec3 pW, in Basis basis, in vec3 winputL, inout int rndSeed)
{
    // Compute the mixture weights and albedos for each lobe
    openpbr_lobe_weights(pW, basis, winputL, rndSeed, lobe_weights, lobe_albedos);
    openpbr_lobe_albedos(pW, basis, winputL, rndSeed, lobe_weights, lobe_albedos);

    // Compute the discrete sampling probability for each lobe
    openpbr_lobe_probabilities(lobe_weights, lobe_albedos, lobe_probs);
}


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// OpenPBR BSDF: evaluation
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

vec3 openpbr_bsdf_evaluate(in vec3 pW, in Basis basis, in vec3 winputL, in vec3 woutputL, inout int rndSeed)
{
    vec3 f = vec3(0.0); // final BRDF
    if (maxComponent(lobe_weights.m[ID_COAT_BRDF]) > 0.0) f += lobe_weights.m[ID_COAT_BRDF] *     coat_brdf_evaluate(pW, basis, winputL, woutputL, rndSeed);
    if (maxComponent(lobe_weights.m[ID_META_BRDF]) > 0.0) f += lobe_weights.m[ID_META_BRDF] *    metal_brdf_evaluate(pW, basis, winputL, woutputL, rndSeed);
    if (maxComponent(lobe_weights.m[ID_SPEC_BRDF]) > 0.0) f += lobe_weights.m[ID_SPEC_BRDF] * specular_brdf_evaluate(pW, basis, winputL, woutputL, rndSeed);
    if (maxComponent(lobe_weights.m[ID_SPEC_BTDF]) > 0.0) f += lobe_weights.m[ID_SPEC_BTDF] * specular_btdf_evaluate(pW, basis, winputL, woutputL, rndSeed);
    if (maxComponent(lobe_weights.m[ID_DIFF_BRDF]) > 0.0) f += lobe_weights.m[ID_DIFF_BRDF] *  diffuse_brdf_evaluate(pW, basis, winputL, woutputL);
    return f;
}


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// OpenPBR BSDF: sampling
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct LobePDFs
{ 
    float m[7];
};

void openpbr_bsdf_lobe_pdfs(in vec3 pW, in Basis basis, in vec3 winputL, in vec3 woutputL,
                            in int skip_lobe_id, inout LobePDFs pdfs)
{
    if (skip_lobe_id != ID_FUZZ_BRDF && maxComponent(lobe_weights.m[ID_FUZZ_BRDF]) > 0.0) pdfs.m[ID_FUZZ_BRDF] = 0.0; //fuzz_brdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_COAT_BRDF && maxComponent(lobe_weights.m[ID_COAT_BRDF]) > 0.0) pdfs.m[ID_COAT_BRDF] =     coat_brdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_META_BRDF && maxComponent(lobe_weights.m[ID_META_BRDF]) > 0.0) pdfs.m[ID_META_BRDF] =    metal_brdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_SPEC_BRDF && maxComponent(lobe_weights.m[ID_SPEC_BRDF]) > 0.0) pdfs.m[ID_SPEC_BRDF] = specular_brdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_SPEC_BTDF && maxComponent(lobe_weights.m[ID_SPEC_BTDF]) > 0.0) pdfs.m[ID_SPEC_BTDF] = specular_btdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_DIFF_BRDF && maxComponent(lobe_weights.m[ID_DIFF_BRDF]) > 0.0) pdfs.m[ID_DIFF_BRDF] =  diffuse_brdf_pdf(pW, basis, winputL, woutputL);
    if (skip_lobe_id != ID_SSSC_BTDF && maxComponent(lobe_weights.m[ID_SSSC_BTDF]) > 0.0) pdfs.m[ID_SSSC_BTDF] = 0.0; //subsurface_btdf_pdf(pW, basis, winputL, woutputL);
}

float openpbr_bsdf_total_pdf(in LobePDFs pdfs)
{
    // Compute total PDF of sampled output direction (according to 1-sample MIS)
    float pdf_woutputL = 0.0;
    if (maxComponent(lobe_weights.m[ID_FUZZ_BRDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_FUZZ_BRDF] * pdfs.m[ID_FUZZ_BRDF];
    if (maxComponent(lobe_weights.m[ID_COAT_BRDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_COAT_BRDF] * pdfs.m[ID_COAT_BRDF];
    if (maxComponent(lobe_weights.m[ID_META_BRDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_META_BRDF] * pdfs.m[ID_META_BRDF];
    if (maxComponent(lobe_weights.m[ID_SPEC_BRDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_SPEC_BRDF] * pdfs.m[ID_SPEC_BRDF];
    if (maxComponent(lobe_weights.m[ID_SPEC_BTDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_SPEC_BTDF] * pdfs.m[ID_SPEC_BTDF];
    if (maxComponent(lobe_weights.m[ID_DIFF_BRDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_DIFF_BRDF] * pdfs.m[ID_DIFF_BRDF];
    if (maxComponent(lobe_weights.m[ID_SSSC_BTDF]) > 0.0) pdf_woutputL += lobe_probs.m[ID_SSSC_BTDF] * pdfs.m[ID_SSSC_BTDF];
    return pdf_woutputL;
}

vec3 openpbr_bsdf_sample(in vec3 pW, in Basis basis, in vec3 winputL,
                         out vec3 woutputL, out float pdf_woutputL, inout int rndSeed)
{
    // Sample a lobe according to these probabilities.
    // Also compute PDF of all other lobes in the sampled direction.
    float X = rand(rndSeed);
    float CDF = 0.0;
    for (int lobe_id=0; lobe_id<NUM_LOBES; ++lobe_id)
    {
        CDF += lobe_probs.m[lobe_id];
        if (X < CDF)
        {
            // Sample this lobe for the output direction woutputL
            float pdf_lobe;
            if      (lobe_id==ID_FUZZ_BRDF) {   } //fuzz_brdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed); }
            else if (lobe_id==ID_COAT_BRDF) {     coat_brdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);   }
            else if (lobe_id==ID_META_BRDF) {    metal_brdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);   }
            else if (lobe_id==ID_SPEC_BRDF) { specular_brdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);  }
            else if (lobe_id==ID_SPEC_BTDF) { specular_btdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);  }
            else if (lobe_id==ID_DIFF_BRDF) {  diffuse_brdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);   }
            else                            {   } //sss_btdf_sample(pW, basis, winputL, woutputL, pdf_lobe, rndSeed);  }

            // Evaluate the PDF of all other lobes at the sampled woutputL
            LobePDFs pdfs;
            openpbr_bsdf_lobe_pdfs(pW, basis, winputL, woutputL, lobe_id, pdfs);
            pdfs.m[lobe_id] = pdf_lobe;

            // Thus compute the PDF of the total BRDF, according to 1-sample MIS
            pdf_woutputL = openpbr_bsdf_total_pdf(pdfs);

            // And evaluate the total BRDF 
            return openpbr_bsdf_evaluate(pW, basis, winputL, woutputL, rndSeed);
        }
    }

    pdf_woutputL = 1.0;
    return vec3(0.0);
}


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// OpenPBR BSDF: PDF
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

float openpbr_bsdf_pdf(in vec3 pW, in Basis basis, in vec3 winputL, in vec3 woutputL,
                       inout int rndSeed)
{
    // Evaluate the PDF of all lobes
    LobePDFs pdfs;
    openpbr_bsdf_lobe_pdfs(pW, basis, winputL, woutputL, -1, pdfs);

    // Thus compute the PDF of the total BRDF, according to 1-sample MIS
    return openpbr_bsdf_total_pdf(pdfs);
}


