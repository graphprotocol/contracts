const currentStep = Number(process.env.TEST_DEPLOYMENT_STEP ?? 1)
const testIf = (stepRequired: number) => (stepRequired <= currentStep ? it : it.skip)

export { testIf }
